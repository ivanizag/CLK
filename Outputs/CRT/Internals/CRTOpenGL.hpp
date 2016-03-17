//
//  CRTOpenGL.hpp
//  Clock Signal
//
//  Created by Thomas Harte on 13/02/2016.
//  Copyright © 2016 Thomas Harte. All rights reserved.
//

#ifndef CRTOpenGL_h
#define CRTOpenGL_h

#include "../CRTTypes.hpp"
#include "OpenGL.hpp"
#include "TextureTarget.hpp"
#include "Shader.hpp"
#include "CRTInputBufferBuilder.hpp"
#include "CRTRunBuilder.hpp"

#include <mutex>

namespace Outputs {
namespace CRT {

// Output vertices are those used to copy from an input buffer — whether it describes data that maps directly to RGB
// or is one of the intermediate buffers that we've used to convert from composite towards RGB.
const size_t OutputVertexOffsetOfPosition = 0;
const size_t OutputVertexOffsetOfTexCoord = 4;
const size_t OutputVertexOffsetOfTimestamp = 8;
const size_t OutputVertexOffsetOfLateral = 12;

const size_t OutputVertexSize = 16;

// Input vertices, used only in composite mode, map from the input buffer to temporary buffer locations; such
// remapping occurs to ensure a continous stream of data for each scan, giving correct out-of-bounds behaviour
const size_t InputVertexOffsetOfInputPosition = 0;
const size_t InputVertexOffsetOfOutputPosition = 4;
const size_t InputVertexOffsetOfPhaseAndAmplitude = 8;
const size_t InputVertexOffsetOfPhaseTime = 12;

const size_t InputVertexSize = 16;

// These constants hold the size of the rolling buffer to which the CPU writes
const int InputBufferBuilderWidth = 2048;
const int InputBufferBuilderHeight = 1024;

// This is the size of the intermediate buffers used during composite to RGB conversion
const int IntermediateBufferWidth = 2048;
const int IntermediateBufferHeight = 2048;

// Some internal
const GLsizeiptr InputVertexBufferDataSize = 256 * 1024;


// Runs are divided discretely by vertical syncs in order to put a usable bounds on the uniform used to track
// run age; that therefore creates a discrete number of fields that are stored. This number should be the
// number of historic fields that are required fully to 
const int NumberOfFields = 3;

class OpenGLOutputBuilder {
	private:
		// colour information
		ColourSpace _colour_space;
		unsigned int _colour_cycle_numerator;
		unsigned int _colour_cycle_denominator;
		OutputDevice _output_device;

		// timing information to allow reasoning about input information
		unsigned int _cycles_per_line;
		unsigned int _height_of_display;
		unsigned int _horizontal_scan_period;
		unsigned int _vertical_scan_period;
		unsigned int _vertical_period_divider;

		// The user-supplied visible area
		Rect _visible_area;

		// Other things the caller may have provided.
		char *_composite_shader;
		char *_rgb_shader;

		// Methods used by the OpenGL code
		void prepare_rgb_output_shader();
		void prepare_composite_input_shader();
		void prepare_output_vertex_array();
		void push_size_uniforms(unsigned int output_width, unsigned int output_height);

		// the run and input data buffers
		std::unique_ptr<CRTInputBufferBuilder> _buffer_builder;
		CRTRunBuilder **_run_builders;
		int _run_write_pointer;
		std::shared_ptr<std::mutex> _output_mutex;

		// transient buffers indicating composite data not yet decoded
		std::unique_ptr<CRTRunBuilder> _composite_src_runs;
		uint16_t _composite_src_output_y;

		char *get_output_vertex_shader();

		char *get_output_fragment_shader(const char *sampling_function);
		char *get_rgb_output_fragment_shader();
		char *get_composite_output_fragment_shader();

		char *get_input_vertex_shader();
		char *get_input_fragment_shader();

		char *get_compound_shader(const char *base, const char *insert);

		std::unique_ptr<OpenGL::Shader> rgb_shader_program;
		std::unique_ptr<OpenGL::Shader> composite_input_shader_program, composite_output_shader_program;

		GLuint output_array_buffer, output_vertex_array;
		size_t output_vertices_per_slice;

		GLint windowSizeUniform, timestampBaseUniform;
		GLint boundsOriginUniform, boundsSizeUniform;

		GLuint textureName, shadowMaskTextureName;

		GLuint defaultFramebuffer;

		std::unique_ptr<OpenGL::TextureTarget> compositeTexture;	// receives raw composite levels
		std::unique_ptr<OpenGL::TextureTarget> filteredYTexture;	// receives filtered Y in the R channel plus unfiltered I/U and Q/V in G and B
		std::unique_ptr<OpenGL::TextureTarget> filteredTexture;		// receives filtered YIQ or YUV

	public:
		OpenGLOutputBuilder(unsigned int number_of_buffers, va_list sizes);
		~OpenGLOutputBuilder();

		inline void set_colour_format(ColourSpace colour_space, unsigned int colour_cycle_numerator, unsigned int colour_cycle_denominator)
		{
			_colour_space = colour_space;
			_colour_cycle_numerator = colour_cycle_numerator;
			_colour_cycle_denominator = colour_cycle_denominator;
		}

		inline void set_visible_area(Rect visible_area)
		{
			_visible_area = visible_area;
		}

		inline uint8_t *get_next_input_run()
		{
			if (_output_buffer_data_pointer + 6 * InputVertexSize > InputVertexBufferDataSize) _output_buffer_data_pointer = 0;
			uint8_t *pointer = &_output_buffer_data[_output_buffer_data_pointer];
			_output_buffer_data_pointer += 6 * InputVertexSize;
			return pointer;
//			_output_mutex->lock();
//			return (_output_device == Monitor) ? _run_builders[_run_write_pointer]->get_next_run(6) : _composite_src_runs->get_next_run(2);
		}

		inline void complete_input_run()
		{
			_run_builders[_run_write_pointer]->number_of_vertices += 6;
//			_output_mutex->unlock();
		}

		inline uint8_t *get_next_output_run()
		{
//			_output_mutex->lock();
//			return (_output_device == Monitor) ? _run_builders[_run_write_pointer]->get_next_run(6) : _composite_src_runs->get_next_run(2);
			return nullptr;
		}

		inline void complete_output_run()
		{
//			_output_mutex->unlock();
		}

		inline OutputDevice get_output_device()
		{
			return _output_device;
		}

		inline uint32_t get_current_field_time()
		{
			return _run_builders[_run_write_pointer]->duration;
		}

		inline void add_to_field_time(uint32_t amount)
		{
			_run_builders[_run_write_pointer]->duration += amount;
		}

		inline uint16_t get_composite_output_y()
		{
			return _composite_src_output_y;
		}

		inline void increment_composite_output_y()
		{
			_composite_src_output_y = (_composite_src_output_y + 1) % IntermediateBufferHeight;
		}

		inline void increment_field()
		{
			_run_write_pointer = (_run_write_pointer + 1)%NumberOfFields;
			_run_builders[_run_write_pointer]->start = _output_buffer_data_pointer;
			_run_builders[_run_write_pointer]->duration = 0;
			_run_builders[_run_write_pointer]->number_of_vertices = 0;
		}

		inline void allocate_write_area(size_t required_length)
		{
			_output_mutex->lock();
			_buffer_builder->allocate_write_area(required_length);
			_output_mutex->unlock();
		}

		inline void reduce_previous_allocation_to(size_t actual_length)
		{
			_buffer_builder->reduce_previous_allocation_to(actual_length);
		}

		inline uint8_t *get_write_target_for_buffer(int buffer)
		{
			return _buffer_builder->get_write_target_for_buffer(buffer);
		}

		inline uint16_t get_last_write_x_posiiton()
		{
			return _buffer_builder->_write_x_position;
		}

		inline uint16_t get_last_write_y_posiiton()
		{
			return _buffer_builder->_write_y_position;
		}

		void draw_frame(unsigned int output_width, unsigned int output_height, bool only_if_dirty);
		void set_openGL_context_will_change(bool should_delete_resources);
		void set_composite_sampling_function(const char *shader);
		void set_rgb_sampling_function(const char *shader);
		void set_output_device(OutputDevice output_device);
		inline void set_timing(unsigned int cycles_per_line, unsigned int height_of_display, unsigned int horizontal_scan_period, unsigned int vertical_scan_period, unsigned int vertical_period_divider)
		{
			_cycles_per_line = cycles_per_line;
			_height_of_display = height_of_display;
			_horizontal_scan_period = horizontal_scan_period;
			_vertical_scan_period = vertical_scan_period;
			_vertical_period_divider = vertical_period_divider;

			// TODO: update related uniforms
		}

		uint8_t *_output_buffer_data;
		size_t _output_buffer_data_pointer;
};

}
}

#endif /* CRTOpenGL_h */
