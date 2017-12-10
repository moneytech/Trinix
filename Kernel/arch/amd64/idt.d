﻿/**
 * Copyright (c) Rikarin and contributors. All rights reserved.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */
module arch.amd64.idt;

import arch.amd64.registers;
import arch.amd64.pic;
import common.bitfield;
import io.ioport;

alias irq = (byte x) => cast(byte)(0x20 + x);


abstract final class IDT {
@safe: nothrow:
	alias InterruptCallback = @safe void function(Registers* regs);
	
    private __gshared Base m_base;
    private __gshared Descriptor[256] m_entries;
	private __gshared InterruptCallback[256] m_handlers;
    

    static void init() @trusted {
        m_base.limit = Descriptor.sizeof * m_entries.length - 1;
        m_base.base  = cast(ulong)m_entries.ptr;
        
		initJumps();
		flush();
		
		register(0x0D, &onGPF);

		asm pure nothrow {
			sti;
		}
    }
	
	static void flush() @trusted {
		auto base = &m_base;
	
		asm pure nothrow {
			mov RAX, base;
			lidt [RAX];
		}
	}
	
	static void register(uint id, InterruptCallback callback) {
		m_handlers[id] = callback;
	}
	
	static VAddr registerGate(uint id, VAddr func) {
		VAddr ret;
		
		with (desc[id]) {
			ret = ((cast(ulong)targetHi << 32UL) | (cast(ulong)targetMid << 16UL) | cast(ulong)targetLo);
		}
			
        setGate(id, SystemSegmentType.InterruptGate, funcPtr, 0, InterruptStackType.RegisterStack);
		return ret;
    }
	
	private static void setGate(uint id, SystemSegmentType gateType, ulong funcPtr, ushort dplFlags, ushort istFlags) {
        with (m_entries[num]) {
            targetLo  = funcPtr & 0xFFFF;
            segment   = 0x08;
            ist       = istFlags;
            p         = true;
            dpl       = dplFlags;
            type      = cast(uint)gateType;
            targetMid = (funcPtr >> 16) & 0xFFFF;
            targetHi  = (funcPtr >> 32);
        }
    }
	
	private static void initJumps() {
		mixin(GenerateIDT!50);
		
		setGate(3,      SystemSegmentType.InterruptGate, cast(ulong)&isr3,      3, InterruptStackType.Debug);
		setGate(8,      SystemSegmentType.InterruptGate, cast(ulong)&isrIgnore, 0, InterruptStackType.RegisterStack);
		setGate(irq(1), SystemSegmentType.InterruptGate, cast(ulong)&isrIgnore, 0, InterruptStackType.RegisterStack);
		setGate(irq(4), SystemSegmentType.InterruptGate, cast(ulong)&isrIgnore, 0, InterruptStackType.RegisterStack);
	}
	
	extern(C) private static void isrCommon() @trusted {
        asm pure nothrow {
            naked;
            cli;

            /* Save context */
            push RAX;
            push RBX;
            push RCX;
            push RDX;
            push RSI;
            push RDI;
            push RBP;
            push R8;
            push R9;
            push R10;
            push R11;
            push R12;
            push R13;
            push R14;
            push R15;
            
            /* Call dispatcher */
            mov RDI, RSP;
            call isrHandler;
            
            /* Restore context */
            pop R15;
            pop R14;
            pop R13;
            pop R12;
            pop R11;
            pop R10;
            pop R9;
            pop R8;
            pop RBP;
            pop RDI;
            pop RSI;
            pop RDX;
            pop RCX;
            pop RBX;
            pop RAX;

            add RSP, 16;
            db 0x48, 0xCF; // iretq;
        }
    }
	
	private static void isrIgnore() @trusted {
        asm pure nothrow {
            naked;
			cli;
            nop;
            nop;
            nop;

            db 0x48, 0xCF; // iretq;
        }
    }
	
	extern(C) private static isrHandler(Registers* r) {
		r.intNumber &= 0xFF;
		
		if (PIC.isEnabled && irq(0) <= r.intNumber && r.intNumber <= irq(16)) {
			if (r.intNumber >= irq(8)) {
				outPort!ubyte(0xA0, 0x20);
			}
			
			outPort!ubyte(0x20, 0x20);
		}
		
		if (auto x = m_handlers[r.intNumber]) {
			x(r);
		} else {
			// TODO: print unhandled interrupt
		}
	}
	
	private void onGPF(Registers* r) {
		// TODO: print GPF
	
		while (true) {
			asm @trusted pure nothrow {
				hlt;
			}
		}
	}
	
	
	
	
	
	
	

    
    private static template GenerateIDT(uint numberISRs, uint idx = 0) {
        static if (numberISRs == idx)
            const char[] GenerateIDT = ``;
        else
            const char[] GenerateIDT = `SetInterruptGate(` ~ idx.stringof ~ `, &isr` ~ idx.stringof[0 .. $ - 1] ~ `);` ~ GenerateIDT!(numberISRs, idx + 1);
        //TODO: q{} syntax
    }

    private static template GenerateISR(ulong num, bool needDummyError = true) {
        const char[] GenerateISR = `
            private static void isr` ~ num.stringof[0 .. $ - 2] ~ `() {
                asm { naked;` ~
                    (needDummyError ? `push 0UL;` : ``) ~
                    `push ` ~ num.stringof ~ `;` ~
                    `jmp ISRCommon;` ~
                        `
                }
            }
        `;
        
        //TODO: q{} syntax
    }

    private static template GenerateISRs(uint start, uint end, bool needDummyError = true) {
        static if (start > end)
            const char[] GenerateISRs = ``;
        else
            const char[] GenerateISRs = GenerateISR!(start, needDummyError)
            ~ GenerateISRs!(start + 1, end, needDummyError);
    }

    mixin(GenerateISR!0);
    mixin(GenerateISR!1);
    mixin(GenerateISR!2);
    mixin(GenerateISR!3);
    mixin(GenerateISR!4);
    mixin(GenerateISR!5);
    mixin(GenerateISR!6);
    mixin(GenerateISR!7);
    mixin(GenerateISR!(8, false));
    mixin(GenerateISR!9);
    mixin(GenerateISR!(10, false));
    mixin(GenerateISR!(11, false));
    mixin(GenerateISR!(12, false));
    mixin(GenerateISR!(13, false));
    mixin(GenerateISR!(14, false));
    mixin(GenerateISRs!(15, 49));
    
    private static void Dispatch(InterruptStack* stack) {
        Thread.Current.SavedState.SSEInt.Save();

        if (stack.IntNumber == 0xE) { //TODO: remove this. chain: IDT.Dispatch > Task.SendInterruptToThread
            Log.Emergency(`===> Spadlo to -.-"`);
            Log(*stack);

            Port.Cli();
            Port.Hlt();
        } else if (stack.IntNumber < 32) {
            if (Thread.Current.ID == 1) {
                DeviceManager.DumpStack(*stack);
                Port.Cli();
                Port.Halt();
            } else
                Thread.Current.Fault(stack.IntNumber);
        } else
            DeviceManager.Handler(*stack);

        /* We must disable interrupts before sending ACK. Enable it with iretq */
        Port.Cli();
        if (stack.IntNumber >= 32)
            DeviceManager.EOI(cast(int)stack.IntNumber - 32);

        Thread.Current.SavedState.SSEInt.Load();
    }
}


enum InterruptStackType : ushort {
	RegisterStack,
	StackFault,
	DoubleFault,
	NMI,
	Debug,
	MCE
}

enum InterruptType : ubyte {
	DivisionByZero,
	Debug,
	NMI,
	Breakpoint,
	Overflow,
	OutOfBounds,
	InvalidOpcode,
	CoprocessorNotAvailable,
	DoubleFault,
	CoprocessorSegmentOverrun,
	InvalidTaskStateSegment,
	SegmentNotPresent,
	StackFault,
	GeneralProtectionFault,
	PageFault,
	UnknownInterrupt,
	CoprocessorFault,
	AlignmentCheck,
	MachineCheck,
	SimdFloatingPointException
}

enum SystemSegmentType : ubyte {
    LocalDescriptorTable = 0b0010,
    AvailableTSS         = 0b1001,
    BusyTSS              = 0b1011,
    CallGate             = 0b1100,
    InterruptGate        = 0b1110,
    TrapGate             = 0b1111
}


private struct Base {
align(1):
	ushort limit;
	ulong  base;
}

private struct Descriptor {
align(1):
	ushort         targetLo;
	ushort         segment;
	private ushort m_flags;
	ushort         targetMid;
	uint           targetHi;
	private uint   _reserved_0;
	
	mixin(bitfield!(m_flags, "ist", 3, "zero0", 5, "type", 4, "zero1", 1, "dpl", 2, "p", 1));
}

static assert(Base.sizeof == 10);
static assert(Descriptor.sizeof == 16);
