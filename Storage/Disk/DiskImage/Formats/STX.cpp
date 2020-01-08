//
//  STX.cpp
//  Clock Signal
//
//  Created by Thomas Harte on 13/11/2019.
//  Copyright © 2019 Thomas Harte. All rights reserved.
//

#include "STX.hpp"

#include "../../Encodings/MFM/Constants.hpp"
#include "../../Encodings/MFM/Shifter.hpp"
#include "../../Encodings/MFM/Encoder.hpp"
#include "../../Track/PCMTrack.hpp"

#include "Utility/ImplicitSectors.hpp"

#include <array>
#include <cstdlib>

using namespace Storage::Disk;

namespace {

class TrackConstructor {
	public:

};

}

STX::STX(const std::string &file_name) : file_(file_name) {
	// Require that this be a version 3 Pasti.
	if(!file_.check_signature("RSY", 4)) throw Error::InvalidFormat;
	if(file_.get16le() != 3) throw Error::InvalidFormat;

	// Skip: tool used, 2 reserved bytes.
	file_.seek(4, SEEK_CUR);

	// Grab the track count and test for a new-style encoding, and skip a reserved area.
	track_count_ = file_.get8();
	is_new_format_ = file_.get8() == 2;
	file_.seek(4, SEEK_CUR);

	// Set all tracks absent.
	memset(offset_by_track_, 0, sizeof(offset_by_track_));

	// Parse the tracks table to fill in offset_by_track_. The only available documentation
	// for STX is unofficial and makes no promise about track order. Hence the bucket sort,
	// effectively putting them into track order.
	//
	//	Track descriptor layout:
	//
	//	0	4	Record size.
	//	4	4	Number of bytes in fuzzy mask record.
	//	8	2	Number of sectors on track.
	//	10	2	Track flags.
	//	12	2	Total number of bytes on track.
	//	14	1	Track number (b7 = side, b0-b6 = track).
	//	15	1	Track type.
	while(true) {
		const long offset = file_.tell();
		const uint32_t size = file_.get32le();
		if(file_.eof()) break;

		// Skip fields other than track position, then fill in table position and advance.
		file_.seek(10, SEEK_CUR);

		const uint8_t track_position = file_.get8();
		offset_by_track_[track_position] = offset;

		// Seek next track start.
		file_.seek(offset + size, SEEK_SET);
	}
}

HeadPosition STX::get_maximum_head_position() {
	return HeadPosition(80);
}

int STX::get_head_count() {
	return 2;
}

std::shared_ptr<::Storage::Disk::Track> STX::get_track_at_position(::Storage::Disk::Track::Address address) {
	// These images have two sides, at most.
	if(address.head > 1) return nullptr;

	// If no track was found, there's nothing to do here.
	const int track_index = (address.head * 0x80) + address.position.as_int();
	if(!offset_by_track_[track_index]) return nullptr;

	// Seek to the track (skipping the record size field).
	file_.seek(offset_by_track_[track_index] + 4, SEEK_SET);

	// Grab the track description.
	const uint32_t fuzzy_size = file_.get32le();
	const uint16_t sector_count = file_.get16le();
	const uint16_t flags = file_.get16le();
	const size_t track_length = size_t(file_.get16le() << 3);	// Convert bytes to bits.
	file_.seek(2, SEEK_CUR);		// Skip track type; despite being named, it's apparently unused.

	// If this is a trivial .ST-style sector dump, life is easy.
	if(!(flags & 1)) {
		const auto sector_contents = file_.read(sector_count * 512);
		return track_for_sectors(sector_contents.data(), sector_count, uint8_t(address.position.as_int()), uint8_t(address.head), 1, 2, true);
	}

	// Grab sector records, if provided.
	struct Sector {
		// Records explicitly present in the sector table.
		uint32_t data_offset = 0;
		size_t bit_position = 0;
		uint16_t data_duration = 0;
		uint8_t address[6] = {0, 0, 0, 0, 0, 0};
		uint8_t status = 0;

		// Other facts that will either be supplied by the STX or which
		// will be empty.
		std::vector<uint8_t> fuzzy_mask;
		std::vector<uint8_t> contents;

		// Information accumulated locally during processing.
		bool address_has_crc = true;
		size_t track_offset_of_header = 0;
		size_t track_offset_of_data = 0;

		// Accessors.
		uint32_t data_size() {
			return uint32_t(128 << address[3]);
		}
	};
	std::vector<Sector> sectors;
	if(flags & 1) {
		// Read sector records first.
		for(uint16_t c = 0; c < sector_count; ++c) {
			sectors.emplace_back();
			sectors.back().data_offset = file_.get32le();
			sectors.back().bit_position = file_.get16le();
			sectors.back().data_duration = file_.get16le();
			file_.read(sectors.back().address, 6);
			sectors.back().status = file_.get8();
			file_.seek(1, SEEK_CUR);
		}

		// Now read fuzzy masks, if available.
		if(fuzzy_size) {
			uint32_t fuzzy_bytes_read = 0;
			for(auto &sector: sectors) {
				// Check for the fuzzy bit mask; if it's not set then
				// there's nothing for this sector.
				if(!(sector.status & 0x80)) continue;

				// Make sure there are enough bytes left.
				const uint32_t expected_bytes = sector.data_size();
				if(fuzzy_bytes_read + expected_bytes > fuzzy_size) break;

				// Okay, there are, so read them.
				sector.fuzzy_mask = file_.read(expected_bytes);
				fuzzy_bytes_read += expected_bytes;
			}

			// It should be true that the number of fuzzy masks caused
			// exactly the correct number of fuzzy bytes to be read.
			// But, just in case, check and possibly skip some.
			file_.seek(long(fuzzy_size) - fuzzy_bytes_read, SEEK_CUR);
		}
	} else {
		// No sector records, so there should be no fuzzy records.
		// Skip the supplied size, just in case.
		file_.seek(fuzzy_size, SEEK_CUR);
	}

	// From here: there's either a track image or there isn't.
	//
	// If there is then it may or may not contain the sector bodies.
	// The sectors themselves will be the guide — if they have
	// offsets within the track image then that's that; if it's
	// outside then that implies extra sector contents.
	//
	// If there isn't a track image at all then either the sectors
	// were explicit or they're completely implicit, like an ST file.

	// Grab the read-track-esque track contents, if available.
	std::vector<uint8_t> track_data;
	long sector_start = file_.tell();
	if(flags & 0x40) {
		if(flags & 0x80) {
			const uint16_t first_sync = file_.get16le();
			const uint16_t image_size = file_.get16le();
			track_data = file_.read(image_size);

			// TODO: and encode... ignoring sector contents?
			(void)first_sync;
		} else {
			const uint16_t image_size = file_.get16le();
			track_data = file_.read(image_size);
		}
	}

	// Grab all sector contents.
	if(sectors.empty()) {
		// No explicit sectors were given, so create the implied sort.
		for(int c = 0; c < sector_count; ++c) {
			sectors.emplace_back();
			sectors.back().address[0] = uint8_t(address.position.as_int());	// Track.
			sectors.back().address[1] = uint8_t(address.head);	// Head.
			sectors.back().address[2] = uint8_t(c + 1);	// Sector.
			sectors.back().address[3] = uint8_t(c + 1);	// Size.
			sectors.back().address_has_crc = false;

			sectors.back().contents = file_.read(512);
			sectors.back().bit_position = size_t(c);	// For the sake of ordering only.
		}
	} else {
		long end_of_data = file_.tell();
		for(auto &sector: sectors) {
			if(!(sector.status & 0x10)) {
				file_.seek(sector.data_offset + sector_start, SEEK_SET);
				sector.contents = file_.read(sector.data_size());
				end_of_data = std::max(end_of_data, file_.tell());
			}
		}
		file_.seek(end_of_data, SEEK_SET);
	}

	// Check for timing info.
	if(is_new_format_) {
		// Do something, do something, else, else.
	}

	/*
		Having reached here:

			* 	if track_data is not empty, it is what you'd see from a read track command;
			* 	the vector of sectors will contain sectors to be written; contents will be populated,
				and each individually may or may not have a fuzzy_mask and/or timing.

		Also note track_length, which is the perceived length of the track, rounded to whole bytes.
	*/

	// Sort the sectors by starting position. It's perfectly possible that they're always
	// sorted in STX but, again, the reverse-engineered documentation doesn't make the
	// promise, so that's that.
	std::sort(sectors.begin(), sectors.end(), [] (Sector &lhs, Sector &rhs) { return lhs.bit_position < rhs.bit_position; });

	if(track_data.empty()) {

	} else {
		// Locate things that might be ID or data address marks; as a side effect of the way
		// this is implemented, the byte_locations will be set to the first bit of apparent
		// content for an ID or data mark.
		struct PotentialMark {
			enum class Type { ID, Data } type;
			size_t byte_location;

			PotentialMark(Type type, size_t byte_location) : type(type), byte_location(byte_location) {}
		};
		std::vector<PotentialMark> potential_marks;
		{
			const uint32_t id_mark = 0xa1a1fe;
			const uint32_t data_mark = 0xa1a1fb;
			uint32_t shifter = 0;
			for(size_t c = 0; c < track_data.size(); ++c) {
				shifter = ((shifter << 8) | track_data[c]) & 0xffffff;

				if(shifter == id_mark) {
					potential_marks.emplace_back(PotentialMark::Type::ID, c);
				} else if(shifter == data_mark) {
					potential_marks.emplace_back(PotentialMark::Type::Data, c);
				}
			}
		}

		// For each sector that exists, locate the correlated potential marks.
		// Since sectors are now in track order, a forward walk through potential
		// marks should work.
		auto next_mark = potential_marks.begin();
		for(auto &sector: sectors) {
			if(sector.data_offset < track_data.size()) {
				// The sector already tells us where its body is, so life is easy.
				// Link the body to its known position, and backtrack to find the ID.
				sector.track_offset_of_data = sector.data_offset;

				// Search for an unconsumed data mark at this location.
				auto data_search = next_mark;
				while(
					data_search != potential_marks.end() &&
					!(data_search->type == PotentialMark::Type::Data && data_search->byte_location == sector.track_offset_of_data))
					++data_search;

				// Advance the potential mark consumption pointer.
				next_mark = data_search + 1;

				// Recede to a previous ID mark if possible.
				while(data_search >= potential_marks.begin() &&
					!(data_search->type == PotentialMark::Type::ID && data_search->byte_location >= sector.track_offset_of_data - 150))
					--data_search;

				if(data_search >= potential_marks.begin()) {
					sector.track_offset_of_header = data_search->byte_location;
				} else {
					// Couldn't figure this one out; just make a geuss.
					sector.track_offset_of_header = sector.track_offset_of_data - 50;
				}
			} else {
				// For either approach below, the next ID is needed.
				while(next_mark != potential_marks.end() && next_mark->type != PotentialMark::Type::ID)
					++next_mark;

				if(next_mark == potential_marks.end()) break;

				// This sector's body isn't accurately represented within the read track
				// image (or, at least, isn't decalred to be), so look for a suitable
				// ID mark and then — if it has a body — consume the next data mark too.
				if(sector.status & 0x10) {
					// There's no placement information to go from, so compare by ID fields. As long
					// as at least two bytes match, that'll do. Arbitrarily.
					int matches = 0;
					for(size_t c = 0; c < 4; ++c) {
						matches += track_data[next_mark->byte_location + c] == sector.address[c];
					}
					if(matches >= 2) {
						sector.track_offset_of_header = next_mark->byte_location;
						++ next_mark;
					} else {
						// Desperation. The meaning of bit_position versus the track_contents is
						// fairly undefined at the best of times, but seems to correlate with data
						// rather than the header anyway. So, ummm...
						sector.track_offset_of_header = sector.bit_position >> 3;
					}
				} else {
					// If the next potential marks are an ID/data pair, and the stated data location is within
					// 100 bytes of that encoded in the sector, take it.
					auto data_mark = next_mark + 1;
					if(
						next_mark->type == PotentialMark::Type::ID &&
						data_mark->type == PotentialMark::Type::Data &&
						std::abs(int(next_mark->byte_location - (sector.bit_position >> 3))) < 100) {
						sector.track_offset_of_header = next_mark->byte_location;
						sector.track_offset_of_data = data_mark->byte_location;
						next_mark += 2;
					} else {
						// Don't know. TODO?
					}
				}
			}
		}


		// The game: take bytes from track_data unless or until a sector is hit.
		auto next_sector = sectors.begin();
		size_t bytes_consumed = 0;
		std::unique_ptr<Encodings::MFM::Encoder> encoder;
		std::unique_ptr<PCMSegment> segment;
		while(bytes_consumed < track_length) {
			// Next event is either the next sector or the end of the track. Let's see.
			size_t bytes_to_consume =
				((next_sector != sectors.end()) ?
					next_sector->track_offset_of_header : track_length) - bytes_consumed;

			// Write from bits_written to bits_written + bits_to_consume from track_data
			// to an encoder. If there is no encoder right now, create one.
			if(!encoder) {
				segment.reset(new PCMSegment);
				encoder = Encodings::MFM::GetMFMEncoder(segment->data);
			}

			// Output bytes up to the sector.
			while(bytes_to_consume--) {
				encoder->add_byte(track_data[bytes_consumed]);
				++bytes_consumed;
			}

			// Chuck out a sector if it's time for one.
			if(next_sector != sectors.end()) {
				// Output header.
				encoder->add_ID_address_mark();					// This is four 'bytes', but pretend it's three.
				encoder->add_byte(next_sector->address[0]);
				encoder->add_byte(next_sector->address[1]);
				encoder->add_byte(next_sector->address[2]);
				encoder->add_byte(next_sector->address[3]);
				if(next_sector->address_has_crc) {
					encoder->add_byte(next_sector->address[4]);
					encoder->add_byte(next_sector->address[5]);
				} else {
					encoder->add_crc((next_sector->status & 0x18) == 0x18);
				}
				bytes_consumed += 9;

				if(!(next_sector->status & 0x10)) {
					while(bytes_consumed < next_sector->track_offset_of_data) {
						encoder->add_byte(track_data[bytes_consumed]);
						++bytes_consumed;
					}

					encoder->add_data_address_mark();		// Also four bytes, which we'll model as three.
					for(const auto byte: next_sector->contents) {
						encoder->add_byte(byte);
					}
					encoder->add_crc(next_sector->status & 0x8);
					bytes_consumed += next_sector->contents.size() + 5;
				}

				++next_sector;
			}
		}

		return std::make_shared<PCMTrack>(*segment);
	}

	return nullptr;
}
