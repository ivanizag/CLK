//
//  i8272.cpp
//  Clock Signal
//
//  Created by Thomas Harte on 05/08/2017.
//  Copyright © 2017 Thomas Harte. All rights reserved.
//

#include "i8272.hpp"

#include <cstdio>

using namespace Intel;

namespace {
const uint8_t StatusRQM = 0x80;	// Set indicates: ready to send or receive from processor.
}

i8272::i8272(Cycles clock_rate, int clock_rate_multiplier, int revolutions_per_minute) :
	Storage::Disk::MFMController(clock_rate, clock_rate_multiplier, revolutions_per_minute),
	status_(StatusRQM),
	interesting_event_mask_((int)Event8272::CommandByte),
	resume_point_(0),
	delay_time_(0) {
	posit_event((int)Event8272::CommandByte);
}

void i8272::run_for(Cycles cycles) {
	Storage::Disk::MFMController::run_for(cycles);
	if(delay_time_ > 0) {
		if(cycles.as_int() >= delay_time_) {
			delay_time_ = 0;
			posit_event((int)Event8272::Timer);
		} else {
			delay_time_ -= cycles.as_int();
		}
	}
}

void i8272::set_register(int address, uint8_t value) {
	// don't consider attempted sets to the status register
	if(!address) return;

	// if not ready for commands, do nothing
	if(!(status_ & StatusRQM)) return;

	// accumulate latest byte in the command byte sequence
	command_.push_back(value);
	posit_event((int)Event8272::CommandByte);
}

uint8_t i8272::get_register(int address) {
	if(address) {
		printf("8272 get data\n");
		return 0xff;
	} else {
		printf("8272 get status\n");
		return status_;
	}
}

#define BEGIN_SECTION()	switch(resume_point_) { default:
#define END_SECTION()	}

#define WAIT_FOR_EVENT(mask)	resume_point_ = __LINE__; interesting_event_mask_ = (int)mask; return; case __LINE__:

void i8272::posit_event(int type) {
	if(!(interesting_event_mask_ & type)) return;
	interesting_event_mask_ &= ~type;

	BEGIN_SECTION();

	wait_for_command:
		set_data_mode(Storage::Disk::MFMController::DataMode::Scanning);
		command_.clear();

	wait_for_complete_command_sequence:
		status_ |= StatusRQM;
		WAIT_FOR_EVENT(Event8272::CommandByte)
		status_ &= ~StatusRQM;

		switch(command_[0] & 0x1f) {
			case 0x06:	// read data
				if(command_.size() < 9) goto wait_for_complete_command_sequence;
				goto read_data;

			case 0x0b:	// read deleted data
				if(command_.size() < 9) goto wait_for_complete_command_sequence;
				goto read_deleted_data;

			case 0x05:	// write data
				if(command_.size() < 9) goto wait_for_complete_command_sequence;
				goto write_data;

			case 0x09:	// write deleted data
				if(command_.size() < 9) goto wait_for_complete_command_sequence;
				goto write_deleted_data;

			case 0x02:	// read track
				if(command_.size() < 9) goto wait_for_complete_command_sequence;
				goto read_track;

			case 0x0a:	// read ID
				if(command_.size() < 2) goto wait_for_complete_command_sequence;
				goto read_id;

			case 0x0d:	// format track
				if(command_.size() < 6) goto wait_for_complete_command_sequence;
				goto format_track;

			case 0x11:	// scan low
				if(command_.size() < 9) goto wait_for_complete_command_sequence;
				goto scan_low;

			case 0x19:	// scan low or equal
				if(command_.size() < 9) goto wait_for_complete_command_sequence;
				goto scan_low_or_equal;

			case 0x1d:	// scan high or equal
				if(command_.size() < 9) goto wait_for_complete_command_sequence;
				goto scan_high_or_equal;

			case 0x07:	// recalibrate
				if(command_.size() < 2) goto wait_for_complete_command_sequence;
				goto recalibrate;

			case 0x08:	// sense interrupt status
				goto sense_interrupt_status;

			case 0x03:	// specify
				if(command_.size() < 3) goto wait_for_complete_command_sequence;
				goto specify;

			case 0x04:	// sense drive status
				if(command_.size() < 2) goto wait_for_complete_command_sequence;
				goto sense_drive_status;

			case 0x0f:	// seek
				if(command_.size() < 3) goto wait_for_complete_command_sequence;
				goto seek;

			default:	// invalid
				goto invalid;
		}

	read_data:
		printf("Read data unimplemented!!");
		goto wait_for_command;

	read_deleted_data:
		printf("Read deleted data unimplemented!!");
		goto wait_for_command;

	write_data:
		printf("Write data unimplemented!!");
		goto wait_for_command;

	write_deleted_data:
		printf("Write deleted data unimplemented!!");
		goto wait_for_command;

	read_track:
		printf("Read track unimplemented!!");
		goto wait_for_command;

	read_id:
		printf("Read ID unimplemented!!");
		goto wait_for_command;

	format_track:
		printf("Fromat track unimplemented!!");
		goto wait_for_command;

	scan_low:
		printf("Scan low unimplemented!!");
		goto wait_for_command;

	scan_low_or_equal:
		printf("Scan low or equal unimplemented!!");
		goto wait_for_command;

	scan_high_or_equal:
		printf("Scan high or equal unimplemented!!");
		goto wait_for_command;

	recalibrate:
		printf("Recalibrate unimplemented!!");
		goto wait_for_command;

	sense_interrupt_status:
		printf("Sense interrupt status unimplemented!!");
		goto wait_for_command;

	specify:
		printf("Specify");
		step_rate_time_ = command_[1] &0xf0;		// i.e. 16 to 240m
		head_unload_time_ = command_[1] & 0x0f;		// i.e. 1 to 16ms
		head_load_time_ = command_[2] & ~1;			// i.e. 2 to 254 ms in increments of 2ms
		dma_mode_ = !(command_[2] & 1);
		goto wait_for_command;

	sense_drive_status:
		printf("Sense drive status unimplemented!!");
		goto wait_for_command;

	seek:
		printf("Seek unimplemented!!");
		goto wait_for_command;

	invalid:
		// A no-op, causing the FDC to go back into standby mode.
		goto wait_for_command;

	END_SECTION()
}
