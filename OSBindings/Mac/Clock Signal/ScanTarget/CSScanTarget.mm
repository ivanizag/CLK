//
//  ScanTarget.m
//  Clock Signal
//
//  Created by Thomas Harte on 02/08/2020.
//  Copyright © 2020 Thomas Harte. All rights reserved.
//

#import "CSScanTarget.h"

#include <atomic>
#import <Metal/Metal.h>
#include "BufferingScanTarget.hpp"

namespace {

struct Uniforms {
	int32_t scale[2];
	float lineWidth;
	float aspectRatioMultiplier;
	simd::float3x3 toRGB;
	simd::float3x3 fromRGB;
};

constexpr size_t NumBufferedScans = 2048;
constexpr size_t NumBufferedLines = 2048;

/// The shared resource options this app would most favour; applied as widely as possible.
constexpr MTLResourceOptions SharedResourceOptionsStandard = MTLResourceCPUCacheModeWriteCombined | MTLResourceStorageModeShared;

/// The shared resource options used for the write-area texture; on macOS it can't be MTLResourceStorageModeShared so this is a carve-out.
constexpr MTLResourceOptions SharedResourceOptionsTexture = MTLResourceCPUCacheModeWriteCombined | MTLResourceStorageModeManaged;

#define uniforms() reinterpret_cast<Uniforms *>(_uniformsBuffer.contents)

}

using BufferingScanTarget = Outputs::Display::BufferingScanTarget;

@implementation CSScanTarget {
	id<MTLCommandQueue> _commandQueue;

	id<MTLFunction> _vertexShader;
	id<MTLFunction> _fragmentShader;

	id<MTLRenderPipelineState> _scanPipeline;
	id<MTLRenderPipelineState> _copyPipeline;

	// Buffers.
	id<MTLBuffer> _uniformsBuffer;

	id<MTLBuffer> _scansBuffer;
	id<MTLBuffer> _linesBuffer;
	id<MTLBuffer> _writeAreaBuffer;

	// Textures.
	id<MTLTexture> _writeAreaTexture;
	size_t _bytesPerInputPixel;
	size_t _totalTextureBytes;

	id<MTLTexture> _frameBuffer;
	MTLRenderPassDescriptor *_frameBufferRenderPass;

	// The scan target in C++-world terms and the non-GPU storage for it.
	BufferingScanTarget _scanTarget;
	BufferingScanTarget::LineMetadata _lineMetadataBuffer[NumBufferedLines];
	std::atomic_bool _isDrawing;

	// The output view's aspect ratio.
	__weak MTKView *_view;
}

- (nonnull instancetype)initWithView:(nonnull MTKView *)view {
	self = [super init];
	if(self) {
		_commandQueue = [view.device newCommandQueue];

		// Allocate space for uniforms.
		_uniformsBuffer = [view.device
			newBufferWithLength:sizeof(Uniforms)
			options:MTLResourceCPUCacheModeWriteCombined | MTLResourceStorageModeShared];

		// Allocate buffers for scans and lines and for the write area texture.
		_scansBuffer = [view.device
			newBufferWithLength:sizeof(Outputs::Display::BufferingScanTarget::Scan)*NumBufferedScans
			options:SharedResourceOptionsStandard];
		_linesBuffer = [view.device
			newBufferWithLength:sizeof(Outputs::Display::BufferingScanTarget::Line)*NumBufferedLines
			options:SharedResourceOptionsStandard];
		_writeAreaBuffer = [view.device
			newBufferWithLength:BufferingScanTarget::WriteAreaWidth*BufferingScanTarget::WriteAreaHeight*4
			options:SharedResourceOptionsTexture];

		// Install all that storage in the buffering scan target.
		_scanTarget.set_write_area(reinterpret_cast<uint8_t *>(_writeAreaBuffer.contents));
		_scanTarget.set_line_buffer(reinterpret_cast<BufferingScanTarget::Line *>(_linesBuffer.contents), _lineMetadataBuffer, NumBufferedLines);
		_scanTarget.set_scan_buffer(reinterpret_cast<BufferingScanTarget::Scan *>(_scansBuffer.contents), NumBufferedScans);

		// Set initial aspect-ratio multiplier.
		_view = view;
		[self mtkView:view drawableSizeWillChange:view.drawableSize];

		// Generate copy pipeline.
		id<MTLLibrary> library = [_view.device newDefaultLibrary];
		MTLRenderPipelineDescriptor *const pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
		pipelineDescriptor.colorAttachments[0].pixelFormat = _view.colorPixelFormat;
		pipelineDescriptor.vertexFunction = [library newFunctionWithName:@"copyVertex"];
		pipelineDescriptor.fragmentFunction = [library newFunctionWithName:@"copyFragment"];
		_copyPipeline = [_view.device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:nil];
	}

	return self;
}

/*!
 @method mtkView:drawableSizeWillChange:
 @abstract Called whenever the drawableSize of the view will change
 @discussion Delegate can recompute view and projection matricies or regenerate any buffers to be compatible with the new view size or resolution
 @param view MTKView which called this method
 @param size New drawable size in pixels
 */
- (void)mtkView:(nonnull MTKView *)view drawableSizeWillChange:(CGSize)size {
	[self setAspectRatio];

	// TODO: consider multisampling here? But it seems like you'd need another level of indirection
	// in order to maintain an ongoing buffer that supersamples only at the end.

	// TODO: attach a stencil buffer.

	@synchronized(self) {
		// Generate a framebuffer and a pipeline that targets it.
		MTLTextureDescriptor *const textureDescriptor = [MTLTextureDescriptor
			texture2DDescriptorWithPixelFormat:view.colorPixelFormat
			width:NSUInteger(size.width * view.layer.contentsScale)
			height:NSUInteger(size.height * view.layer.contentsScale)
			mipmapped:NO];
		textureDescriptor.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
		textureDescriptor.resourceOptions = MTLResourceStorageModePrivate;
		_frameBuffer = [view.device newTextureWithDescriptor:textureDescriptor];

		_frameBufferRenderPass = [[MTLRenderPassDescriptor alloc] init];
		_frameBufferRenderPass.colorAttachments[0].texture = _frameBuffer;
		_frameBufferRenderPass.colorAttachments[0].loadAction = MTLLoadActionLoad;
		_frameBufferRenderPass.colorAttachments[0].storeAction = MTLStoreActionStore;

		// TODO: old framebuffer should be resized onto the new one.
	}
}

- (void)setAspectRatio {
	uniforms()->aspectRatioMultiplier = float(_scanTarget.modals().aspect_ratio / (_view.bounds.size.width / _view.bounds.size.height));
}

- (void)setModals:(const Outputs::Display::ScanTarget::Modals &)modals {
	//
	// Populate uniforms.
	//
	uniforms()->scale[0] = modals.output_scale.x;
	uniforms()->scale[1] = modals.output_scale.y;
	uniforms()->lineWidth = 1.05f / modals.expected_vertical_lines;	// TODO: return to 1.0 (or slightly more), once happy.
	[self setAspectRatio];

	const auto toRGB = to_rgb_matrix(modals.composite_colour_space);
	uniforms()->toRGB = simd::float3x3(
		simd::float3{toRGB[0], toRGB[1], toRGB[2]},
		simd::float3{toRGB[3], toRGB[4], toRGB[5]},
		simd::float3{toRGB[6], toRGB[7], toRGB[8]}
	);

	const auto fromRGB = from_rgb_matrix(modals.composite_colour_space);
	uniforms()->fromRGB = simd::float3x3(
		simd::float3{fromRGB[0], fromRGB[1], fromRGB[2]},
		simd::float3{fromRGB[3], fromRGB[4], fromRGB[5]},
		simd::float3{fromRGB[6], fromRGB[7], fromRGB[8]}
	);



	//
	// Generate input texture.
	//
	MTLPixelFormat pixelFormat;
	_bytesPerInputPixel = size_for_data_type(modals.input_data_type);
	if(data_type_is_normalised(modals.input_data_type)) {
		switch(_bytesPerInputPixel) {
			default:
			case 1: pixelFormat = MTLPixelFormatR8Unorm;	break;
			case 2: pixelFormat = MTLPixelFormatRG8Unorm;	break;
			case 4: pixelFormat = MTLPixelFormatRGBA8Unorm;	break;
		}
	} else {
		switch(_bytesPerInputPixel) {
			default:
			case 1: pixelFormat = MTLPixelFormatR8Uint;		break;
			case 2: pixelFormat = MTLPixelFormatRG8Uint;	break;
			case 4: pixelFormat = MTLPixelFormatRGBA8Uint;	break;
		}
	}
	MTLTextureDescriptor *const textureDescriptor = [MTLTextureDescriptor
		texture2DDescriptorWithPixelFormat:pixelFormat
		width:BufferingScanTarget::WriteAreaWidth
		height:BufferingScanTarget::WriteAreaHeight
		mipmapped:NO];
	textureDescriptor.resourceOptions = SharedResourceOptionsTexture;
	if(@available(macOS 10.14, *)) {
		textureDescriptor.allowGPUOptimizedContents = NO;
	}

	// TODO: the call below is the only reason why this project now requires macOS 10.13; is it all that helpful versus just uploading each frame?
	const NSUInteger bytesPerRow = BufferingScanTarget::WriteAreaWidth * _bytesPerInputPixel;
	_writeAreaTexture = [_writeAreaBuffer
		newTextureWithDescriptor:textureDescriptor
		offset:0
		bytesPerRow:bytesPerRow];
	_totalTextureBytes = bytesPerRow * BufferingScanTarget::WriteAreaHeight;



	//
	// Generate scan pipeline.
	//
	id<MTLLibrary> library = [_view.device newDefaultLibrary];
	MTLRenderPipelineDescriptor *pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
	pipelineDescriptor.colorAttachments[0].pixelFormat = _view.colorPixelFormat;

	// TODO: logic somewhat more complicated than this, probably
	pipelineDescriptor.vertexFunction = [library newFunctionWithName:@"scanToDisplay"];
	switch(modals.input_data_type) {
		case Outputs::Display::InputDataType::Luminance1:
			pipelineDescriptor.fragmentFunction = [library newFunctionWithName:@"sampleLuminance1"];
		break;
		case Outputs::Display::InputDataType::Luminance8:
			pipelineDescriptor.fragmentFunction = [library newFunctionWithName:@"sampleLuminance8"];
		break;
		case Outputs::Display::InputDataType::PhaseLinkedLuminance8:
			pipelineDescriptor.fragmentFunction = [library newFunctionWithName:@"samplePhaseLinkedLuminance8"];
		break;

		case Outputs::Display::InputDataType::Luminance8Phase8:
			pipelineDescriptor.fragmentFunction = [library newFunctionWithName:@"sampleLuminance8Phase8"];
		break;

		case Outputs::Display::InputDataType::Red1Green1Blue1:
			pipelineDescriptor.fragmentFunction = [library newFunctionWithName:@"sampleRed1Green1Blue1"];
		break;
		case Outputs::Display::InputDataType::Red2Green2Blue2:
			pipelineDescriptor.fragmentFunction = [library newFunctionWithName:@"sampleRed2Green2Blue2"];
		break;
		case Outputs::Display::InputDataType::Red4Green4Blue4:
			pipelineDescriptor.fragmentFunction = [library newFunctionWithName:@"sampleRed4Green4Blue4"];
		break;
		case Outputs::Display::InputDataType::Red8Green8Blue8:
			pipelineDescriptor.fragmentFunction = [library newFunctionWithName:@"sampleRed8Green8Blue8"];
		break;
	}

	// Enable blending.
	pipelineDescriptor.colorAttachments[0].blendingEnabled = YES;
	pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
	pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;

	_scanPipeline = [_view.device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:nil];
}

- (void)checkModals {
	// TODO: rethink BufferingScanTarget::perform. Is it now really just for guarding the modals?
	_scanTarget.perform([=] {
		const Outputs::Display::ScanTarget::Modals *const newModals = _scanTarget.new_modals();
		if(newModals) {
			[self setModals:*newModals];
		}
	});
}

- (void)updateFrameBuffer {
	[self checkModals];

	@synchronized(self) {
		if(!_frameBufferRenderPass) return;

		// Generate a command encoder for the view.
		id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
		id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:_frameBufferRenderPass];

		// Drawing. Just scans.
		[encoder setRenderPipelineState:_scanPipeline];

		[encoder setFragmentTexture:_writeAreaTexture atIndex:0];
		[encoder setVertexBuffer:_scansBuffer offset:0 atIndex:0];
		[encoder setVertexBuffer:_uniformsBuffer offset:0 atIndex:1];
		[encoder setFragmentBuffer:_uniformsBuffer offset:0 atIndex:0];

		const auto outputArea = _scanTarget.get_output_area();

		// Ensure texture changes are noted.
		const auto writeAreaModificationStart = size_t(outputArea.start.write_area_x + outputArea.start.write_area_y * 2048) * _bytesPerInputPixel;
		const auto writeAreaModificationEnd = size_t(outputArea.end.write_area_x + outputArea.end.write_area_y * 2048) * _bytesPerInputPixel;
		if(writeAreaModificationStart != writeAreaModificationEnd) {
			if(writeAreaModificationStart < writeAreaModificationEnd) {
				[_writeAreaBuffer didModifyRange:NSMakeRange(writeAreaModificationStart, writeAreaModificationEnd - writeAreaModificationStart)];
			} else {
				[_writeAreaBuffer didModifyRange:NSMakeRange(writeAreaModificationStart, _totalTextureBytes - writeAreaModificationStart)];
				if(writeAreaModificationEnd) {
					[_writeAreaBuffer didModifyRange:NSMakeRange(0, writeAreaModificationEnd)];
				}
			}

		}

		// TEMPORARY: just draw the scans.
		if(outputArea.start.scan != outputArea.end.scan) {
			if(outputArea.start.scan < outputArea.end.scan) {
				[encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4 instanceCount:outputArea.end.scan - outputArea.start.scan baseInstance:outputArea.start.scan];
			} else {
				[encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4 instanceCount:NumBufferedScans - outputArea.start.scan baseInstance:outputArea.start.scan];
				if(outputArea.end.scan) {
					[encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4 instanceCount:outputArea.end.scan];
				}
			}
		}

		// Complete encoding.
		[encoder endEncoding];

		// Add a callback to update the buffer.
		[commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> _Nonnull) {
			self->_scanTarget.complete_output_area(outputArea);
		}];

		// Commit the drawing.
		[commandBuffer commit];
	}
}

/*!
 @method drawInMTKView:
 @abstract Called on the delegate when it is asked to render into the view
 @discussion Called on the delegate when it is asked to render into the view
 */
- (void)drawInMTKView:(nonnull MTKView *)view {
	// Schedule a copy from the current framebuffer to the view; blitting is unavailable as the target is a framebuffer texture.
	id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
	id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:view.currentRenderPassDescriptor];

	[encoder setRenderPipelineState:_copyPipeline];
	[encoder setVertexTexture:_frameBuffer atIndex:0];
	[encoder setFragmentTexture:_frameBuffer atIndex:0];

	[encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
	[encoder endEncoding];

	[commandBuffer presentDrawable:view.currentDrawable];
	[commandBuffer commit];
}

-  (Outputs::Display::ScanTarget *)scanTarget {
	return &_scanTarget;
}

@end
