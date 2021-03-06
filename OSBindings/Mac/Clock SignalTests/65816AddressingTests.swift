//
//  WDC65816AddressingTests.swift
//  Clock Signal
//
//  Created by Thomas Harte on 13/10/2020.
//  Copyright 2020 Thomas Harte. All rights reserved.
//

import Foundation
import XCTest

// This exactly transcribes the examples given in http://6502.org/tutorials/65c816opcodes.html#5
// Quoted text is taken verbatim from that document.
class WDC65816AddressingTests: XCTestCase {

	// MARK: - Test Machines

	/// Returns a CSTestMachine6502 that is currently configured in native mode with 16-bit memory and index registers.
	private func machine16() -> CSTestMachine6502 {
		let machine = CSTestMachine6502(processor: .processor65816)
		machine.setValue(0, for: .emulationFlag)
		machine.setValue(0, for: .flags)
		return machine
	}

	/// Returns a CSTestMachine6502 that is currently configured in emulation mode.
	private func machine8() -> CSTestMachine6502 {
		return CSTestMachine6502(processor: .processor65816)
	}

	// MARK: - Tests

	func testAbsoluteJMP() {
		// "If the K register is $12, then JMP $FFFF jumps to $12FFFF"
		let machine = machine16()

		machine.setValue(0x12, for: .programBank)

		// JMP $ffff
		machine.setData(Data([0x4c, 0xff, 0xff]), atAddress: 0x120200)

		machine.setValue(0x200, for: .programCounter)
		machine.runForNumber(ofCycles: 4)

		XCTAssertEqual(machine.value(for: .programCounter), 0)	// i.e. 0xffff + 1
		XCTAssertEqual(machine.value(for: .programBank), 0x12)
	}

	func testAbsolute() {
		// "If the DBR is $12 and the m flag is 0, then LDA $FFFF loads the low byte of
		// the data from address $12FFFF, and the high byte from address $130000"

		let machine = machine16()

		machine.setValue(0x12, for: .dataBank)

		machine.setValue(0xab, forAddress: 0x12ffff)
		machine.setValue(0xcd, forAddress: 0x130000)

		// LDA $ffff; NOP
		machine.setData(Data([0xad, 0xff, 0xff, 0xea]), atAddress: 0x200)

		machine.setValue(0x200, for: .programCounter)
		machine.runForNumber(ofCycles: 6)

		XCTAssertEqual(machine.value(for: .A), 0xcdab)
	}

	func testAbsoluteX() {
		// "If the DBR is $12, the X register is $000A, and the m flag is 0, then
		// LDA $FFFE,X loads the low byte of the data from address $130008, and
		// the high byte from address $130009"
		//
		// "Note that this is one of the rare instances where emulation mode has
		// different behavior than the 65C02 or NMOS 6502 ..."

		let machine = machine16()

		machine.setValue(0x12, for: .dataBank)
		machine.setValue(0x0a, for: .X)

		machine.setValue(0xab, forAddress: 0x130008)
		machine.setValue(0xcd, forAddress: 0x130009)

		// LDA $fffe, x; NOP
		machine.setData(Data([0xbd, 0xfe, 0xff, 0xea]), atAddress: 0x200)

		machine.setValue(0x200, for: .programCounter)
		machine.runForNumber(ofCycles: 7)

		XCTAssertEqual(machine.value(for: .A), 0xcdab)
	}

	func testJMPAbsoluteIndirect() {
		// "If the K register is $12 and
		//	* $000000 contains $34
		//	* $00FFFF contains $56
		// then JMP ($FFFF) jumps to $123456"

		let machine = machine16()

		machine.setValue(0x12, for: .programBank)
		machine.setValue(0x0a, for: .X)

		machine.setValue(0x34, forAddress: 0x0000)
		machine.setValue(0x56, forAddress: 0xffff)

		// JMP ($ffff); NOP
		machine.setData(Data([0x6c, 0xff, 0xff, 0xea]), atAddress: 0x120200)

		machine.setValue(0x200, for: .programCounter)
		machine.runForNumber(ofCycles: 6)

		XCTAssertEqual(machine.value(for: .programCounter), 0x3456 + 1)
		XCTAssertEqual(machine.value(for: .programBank), 0x12)
	}

	func testIndirectAbsoluteX() {
		// "If the K register is $12, the X register is $000A, and
		//	* $120008 contains $56
		//	* $120009 contains $34
		//then JMP ($FFFE,X) jumps to $123456"

		let machine = machine16()

		machine.setValue(0x12, for: .programBank)
		machine.setValue(0x0a, for: .X)
		machine.setValue(0x56, forAddress: 0x120008)
		machine.setValue(0x34, forAddress: 0x120009)

		// JMP ($fffe, x); NOP
		machine.setData(Data([0x7c, 0xfe, 0xff, 0xea]), atAddress: 0x120200)

		machine.setValue(0x200, for: .programCounter)
		machine.runForNumber(ofCycles: 7)

		XCTAssertEqual(machine.value(for: .programCounter), 0x3456 + 1)
		XCTAssertEqual(machine.value(for: .programBank), 0x12)
	}

	func testDirect8() {
		// "If the D register is $FF00 and the e flag is 1 (note that
		// this means the m flag must be 1), then LDA $FF loads the low
		// byte of the data from address $00FFFF"

		let machine = machine8()

		machine.setValue(0xff00, for: .direct)

		machine.setValue(0xab, forAddress: 0xffff)

		// LDA $ff; NOP
		machine.setData(Data([0xa5, 0xff, 0xea]), atAddress: 0x0200)

		machine.setValue(0x200, for: .programCounter)
		machine.runForNumber(ofCycles: 4)

		XCTAssertEqual(machine.value(for: .A), 0xab)
	}

	func testDirect16() {
		// "If the D register is $FF00 and the m flag is 0 (note that
		// this means the e flag must be 0), then LDA $FF loads the low
		// byte of the data from address $00FFFF, and the high byte
		// from address $000000"

		let machine = machine16()

		machine.setValue(0xff00, for: .direct)

		machine.setValue(0xab, forAddress: 0xffff)
		machine.setValue(0xcd, forAddress: 0x0000)

		// LDA $ff; NOP
		machine.setData(Data([0xa5, 0xff, 0xea]), atAddress: 0x0200)

		machine.setValue(0x200, for: .programCounter)
		machine.runForNumber(ofCycles: 5)

		XCTAssertEqual(machine.value(for: .A), 0xcdab)
	}

	func testDirextX8() {
		// "If the D register is $FF00, the X register is $000A, and
		// the e flag is 1 (note that this means the m flag must be 1),
		// then LDA $FE,X loads the low byte of the data from
		// address $00FF08"

		let machine = machine8()

		machine.setValue(0xff00, for: .direct)
		machine.setValue(0x000a, for: .X)

		machine.setValue(0xab, forAddress: 0xff08)

		// LDA $fe, X; NOP
		machine.setData(Data([0xb5, 0xfe, 0xea]), atAddress: 0x0200)

		machine.setValue(0x200, for: .programCounter)
		machine.runForNumber(ofCycles: 5)

		XCTAssertEqual(machine.value(for: .A), 0xab)
	}

	func testDirectX16() {
		// "If the D register is $FF00, the X register is $000A, and the
		// m flag is 0 (note that this means the e flag must be 0), then
		// LDA $FE,X loads the low byte of the data from address $000008,
		// and the high byte from address $000009"
		let machine = machine16()

		machine.setValue(0xff00, for: .direct)
		machine.setValue(0x000a, for: .X)

		machine.setValue(0xab, forAddress: 0x0008)
		machine.setValue(0xcd, forAddress: 0x0009)

		// LDA $fe, X; NOP
		machine.setData(Data([0xb5, 0xfe, 0xea]), atAddress: 0x0200)

		machine.setValue(0x200, for: .programCounter)
		machine.runForNumber(ofCycles: 6)

		XCTAssertEqual(machine.value(for: .A), 0xcdab)
	}

	func testDirectIndirect8() {
		// "If the D register is $FF00 and the e flag is 1 (note this means the
		// m flag must be 1), then for LDA ($FF), the address of the low byte of
		// the pointer is $00FFFF and the address of the high byte is $00FF00.
		// Furthermore, if the DBR is $12 and
		//	* $00FF00 contains $FF
		//	* $00FFFF contains $FF
		// then LDA ($FF) loads the low byte of the data from address $12FFFF."
		let machine = machine8()

		machine.setValue(0xff00, for: .direct)
		machine.setValue(0x12, for: .dataBank)

		machine.setValue(0xff, forAddress: 0xff00)
		machine.setValue(0xff, forAddress: 0xffff)

		machine.setValue(0xab, forAddress: 0x12ffff)

		// LDA ($ff); NOP
		machine.setData(Data([0xb2, 0xff, 0xea]), atAddress: 0x0200)

		machine.setValue(0x200, for: .programCounter)
		machine.runForNumber(ofCycles: 6)

		XCTAssertEqual(machine.value(for: .A), 0xab)
	}

	func testDirectIndirect16() {
		// "If the D register is $FF00 and the m flag is 0 (note this means the e
		// flag must be 0), then for LDA ($FF), the address of the low byte of the
		// pointer is $00FFFF and the address of the high byte is $000000.
		// Furthermore, if the DBR is $12 and
		//	* $000000 contains $FF
		//	* $00FFFF contains $FF
		// then LDA ($FF) loads the low byte of the data from address $12FFFF, and
		// the high byte from $130000."
		let machine = machine16()

		machine.setValue(0xff00, for: .direct)
		machine.setValue(0x12, for: .dataBank)

		machine.setValue(0xff, forAddress: 0x0000)
		machine.setValue(0xff, forAddress: 0xffff)

		machine.setValue(0xab, forAddress: 0x12ffff)
		machine.setValue(0xcd, forAddress: 0x130000)

		// LDA ($ff); NOP
		machine.setData(Data([0xb2, 0xff, 0xea]), atAddress: 0x0200)

		machine.setValue(0x200, for: .programCounter)
		machine.runForNumber(ofCycles: 7)

		XCTAssertEqual(machine.value(for: .A), 0xcdab)
	}

	func testDirectIndirectLong() {
		// "If the D register is $FF00 and the m flag is 0, then for LDA [$FE], the
		// address of the low byte of the pointer is $00FFFE, the address of the middle
		// byte is $00FFFF, and the address of the high byte is $000000. Furthermore, if
		//	* $000000 contains $12
		//	* $00FFFE contains $FF
		//	* $00FFFF contains $FF
		// then LDA [$FE] loads the low byte of the data from address $12FFFF, and the
		// high byte from $130000."
		let machine = machine16()

		machine.setValue(0xff00, for: .direct)

		machine.setValue(0x12, forAddress: 0x0000)
		machine.setValue(0xff, forAddress: 0xfffe)
		machine.setValue(0xff, forAddress: 0xffff)

		machine.setValue(0xab, forAddress: 0x12ffff)
		machine.setValue(0xcd, forAddress: 0x130000)

		// LDA [$fe]; NOP
		machine.setData(Data([0xa7, 0xfe, 0xea]), atAddress: 0x0200)

		machine.setValue(0x200, for: .programCounter)
		machine.runForNumber(ofCycles: 8)

		XCTAssertEqual(machine.value(for: .A), 0xcdab)
	}

	func testDirectXIndirectX8() {
		// "If the D register is $FF00, the X register is $000A, and the e flag is 1 (note
		// that this means the m flag must be 1), then for LDA ($FE,X), the address of the
		// low byte of the pointer is $00FF08 and the address of the high byte is $00FF09.
		// Furthermore, if the DBR is $12 and
		//	* $00FF08 contains $FF
		//	* $00FF09 contains $FF
		// then LDA ($FE,X) loads the low byte of the data from address $12FFFF."
		let machine = machine8()

		machine.setValue(0xff00, for: .direct)
		machine.setValue(0x000a, for: .X)
		machine.setValue(0x12, for: .dataBank)

		machine.setValue(0xff, forAddress: 0xff08)
		machine.setValue(0xff, forAddress: 0xff09)

		machine.setValue(0xab, forAddress: 0x12ffff)

		// LDA ($fe, x); NOP
		machine.setData(Data([0xa1, 0xfe, 0xea]), atAddress: 0x0200)

		machine.setValue(0x200, for: .programCounter)
		machine.runForNumber(ofCycles: 7)

		XCTAssertEqual(machine.value(for: .A), 0xab)
	}

	func testDirectXIndirect16() {
		// "If the D register is $FF00, the X register is $000A, and the m flag is 0
		// (note that this means the e flag must be 0), then for LDA ($FE,X), the address
		// of the low byte of the pointer is $000008 and the address of the high byte
		// is $000009. Furthermore, if the DBR is $12 and
		//	* $000008 contains $FF
		//	* $000009 contains $FF
		// then LDA ($FE,X) loads the low byte of the data from address $12FFFF, and the
		// high byte from $130000."
		let machine = machine16()

		machine.setValue(0xff00, for: .direct)
		machine.setValue(0x000a, for: .X)
		machine.setValue(0x12, for: .dataBank)

		machine.setValue(0xff, forAddress: 0x0008)
		machine.setValue(0xff, forAddress: 0x0009)

		machine.setValue(0xab, forAddress: 0x12ffff)
		machine.setValue(0xcd, forAddress: 0x130000)

		// LDA ($fe, x); NOP
		machine.setData(Data([0xa1, 0xfe, 0xea]), atAddress: 0x0200)

		machine.setValue(0x200, for: .programCounter)
		machine.runForNumber(ofCycles: 8)

		XCTAssertEqual(machine.value(for: .A), 0xcdab)
	}

	func testIndirectY8() {
		// "If the D register is $FF00 and the e flag is 1 (note that this means the
		// m flag must be 1), then for LDA ($FF),Y, the address of the low byte of the
		// pointer is $00FFFF and the address of the high byte is $00FF00.
		// Furthermore, if the DBR is $12, the Y register is $000A, and
		//	* $00FF00 contains $FF
		//	* $00FFFF contains $FE
		// then LDA ($FF),Y loads the low byte of the data from address $130008."
		//
		// "this is one of the rare instances where emulation mode has
		// different behavior than the 65C02 or NMOS 6502..."
		let machine = machine8()

		machine.setValue(0xff00, for: .direct)
		machine.setValue(0x000a, for: .Y)
		machine.setValue(0x12, for: .dataBank)

		machine.setValue(0xff, forAddress: 0xff00)
		machine.setValue(0xfe, forAddress: 0xffff)

		machine.setValue(0xab, forAddress: 0x130008)

		// LDA ($ff), y; NOP
		machine.setData(Data([0xb1, 0xff, 0xea]), atAddress: 0x0200)

		machine.setValue(0x200, for: .programCounter)
		machine.runForNumber(ofCycles: 7)

		XCTAssertEqual(machine.value(for: .A), 0xab)
	}

	func testIndirectY16() {
		// "If the D register is $FF00 and the m flag is 0 (note that this means the
		// e flag must be 0), then for LDA ($FF),Y, the address of the low byte of the
		// pointer is $00FFFF and the address of the high byte is $000000.
		// Furthermore, if the DBR is $12, the Y register is $000A, and
		//	* $000000 contains $FF
		//	* $00FFFF contains $FE
		// then LDA ($FF),Y loads the low byte of the data from address $130008, and the
		// high byte from $130009."
		let machine = machine16()

		machine.setValue(0xff00, for: .direct)
		machine.setValue(0x000a, for: .Y)
		machine.setValue(0x12, for: .dataBank)

		machine.setValue(0xff, forAddress: 0x0000)
		machine.setValue(0xfe, forAddress: 0xffff)

		machine.setValue(0xab, forAddress: 0x130008)
		machine.setValue(0xcd, forAddress: 0x130009)

		// LDA ($ff), y; NOP
		machine.setData(Data([0xb1, 0xff, 0xea]), atAddress: 0x0200)

		machine.setValue(0x200, for: .programCounter)
		machine.runForNumber(ofCycles: 8)

		XCTAssertEqual(machine.value(for: .A), 0xcdab)
	}

	func testIndirectYLong() {
		// "If the D register is $FF00 and the m flag is 0, then for LDA [$FE],Y, the address
		// of the low byte of the pointer is $00FFFE, the address of the middle byte is $00FFFF,
		// and the address of the high byte is $000000. Furthermore, if the Y register is $000A, and
		//	* $000000 contains $12
		//	* $00FFFE contains $FC
		//	* $00FFFF contains $FF
		// then LDA [$FE],Y loads the low byte of the data from address $130006, and the high byte
		// from $130007."
		let machine = machine16()

		machine.setValue(0xff00, for: .direct)
		machine.setValue(0x000a, for: .Y)
		machine.setValue(0x12, for: .dataBank)

		machine.setValue(0x12, forAddress: 0x0000)
		machine.setValue(0xfc, forAddress: 0xfffe)
		machine.setValue(0xff, forAddress: 0xffff)

		machine.setValue(0xab, forAddress: 0x130006)
		machine.setValue(0xcd, forAddress: 0x130007)

		// LDA [$fe], y; NOP
		machine.setData(Data([0xb7, 0xfe, 0xea]), atAddress: 0x0200)

		machine.setValue(0x200, for: .programCounter)
		machine.runForNumber(ofCycles: 8)

		XCTAssertEqual(machine.value(for: .A), 0xcdab)
	}

	func testAbsoluteLong() {
		// "If the m flag is 0, then LDA $12FFFF loads the low byte of the data from address $12FFFF,
		// and the high byte from address $130000."
		let machine = machine16()

		machine.setValue(0xab, forAddress: 0x12ffff)
		machine.setValue(0xcd, forAddress: 0x130000)

		// LDA $12ffff; NOP
		machine.setData(Data([0xaf, 0xff, 0xff, 0x12, 0xea]), atAddress: 0x0200)

		machine.setValue(0x200, for: .programCounter)
		machine.runForNumber(ofCycles: 7)

		XCTAssertEqual(machine.value(for: .A), 0xcdab)
	}

	func testAbsoluteLongX() {
		// "If the X register is $000A and the m flag is 0, then LDA $12FFFE,X loads the low byte of
		// the data from address $130008, and the high byte from address $130009."
		let machine = machine16()

		machine.setValue(0x000a, for: .X)

		machine.setValue(0xab, forAddress: 0x130008)
		machine.setValue(0xcd, forAddress: 0x130009)

		// LDA $12fffe, x; NOP
		machine.setData(Data([0xbf, 0xfe, 0xff, 0x12, 0xea]), atAddress: 0x0200)

		machine.setValue(0x200, for: .programCounter)
		machine.runForNumber(ofCycles: 7)

		XCTAssertEqual(machine.value(for: .A), 0xcdab)
	}

	func testStackS() {
		// "If the S register is $FF10 and the m flag is 0, then LDA $FA,S loads the low byte
		// of the data from address $00000A, and the high byte from address $00000B."
		let machine = machine16()

		machine.setValue(0xff10, for: .stackPointer)

		machine.setValue(0xab, forAddress: 0x000a)
		machine.setValue(0xcd, forAddress: 0x000b)

		// LDA $fa, s; NOP
		machine.setData(Data([0xa3, 0xfa, 0xea]), atAddress: 0x0200)

		machine.setValue(0x200, for: .programCounter)
		machine.runForNumber(ofCycles: 7)

		XCTAssertEqual(machine.value(for: .A), 0xcdab)
	}

	func testIndirectStackSY() {
		// "If the S register is $FF10 and the m flag is 0, then for LDA ($FA,S),Y, the address
		// of the low byte of the pointer is $00000A and the address of the high byte is $00000B.
		// Furthermore, if the DBR is $12, the Y register is $0050, and
		//	* $00000A contains $F0
		//	* $00000B contains $FF
		// then LDA ($FA,S),Y loads the low byte of the data from address $130040, and the high
		// byte from $130041."
		let machine = machine16()

		machine.setValue(0xff10, for: .stackPointer)
		machine.setValue(0x0050, for: .Y)
		machine.setValue(0x12, for: .dataBank)

		machine.setValue(0xf0, forAddress: 0x000a)
		machine.setValue(0xff, forAddress: 0x000b)

		machine.setValue(0xab, forAddress: 0x130040)
		machine.setValue(0xcd, forAddress: 0x130041)

		// LDA ($fa, s), y; NOP
		machine.setData(Data([0xb3, 0xfa, 0xea]), atAddress: 0x0200)

		machine.setValue(0x200, for: .programCounter)
		machine.runForNumber(ofCycles: 9)

		XCTAssertEqual(machine.value(for: .A), 0xcdab)
	}

}
