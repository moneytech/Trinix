﻿module Architectures.x86_64.Core.IDT;

import Core;
import Library;
import TaskManager;
import Architecture;
import ObjectManager;
import MemoryManager;
import Architectures.x86_64.Core;


public enum InterruptStackType : ushort {
	RegisterStack,
	StackFault,
	DoubleFault,
	NMI,
	Debug,
	MCE
}

public enum InterruptType : uint {
	DivisionByZero,
	Debug,
	NMI,
	Breakpoint,
	INTO,
	OutOfBounds,
	InvalidOpcode,
	NoCoprocessor,
	DoubleFault,
	CoprocessorSegmentOverrun,
	BadTSS,
	SegmentNotPresent,
	StackFault,
	GeneralProtectionFault,
	PageFault,
	UnknownInterrupt,
	CoprocessorFault,
	AlignmentCheck,
	MachineCheck,
}


public abstract final class IDT : IStaticModule {
	private __gshared IDTBase _idtBase;
	private __gshared InterruptGateDescriptor[256] _entries;
	

	public static bool Initialize() {
		_idtBase.Limit = (InterruptGateDescriptor.sizeof * _entries.length) - 1;
		_idtBase.Base = cast(ulong)_entries.ptr;
		
		mixin(GenerateIDT!50);
		
		SetSystemGate(3, &isr3, InterruptStackType.Debug);
		SetInterruptGate(8, &IsrIgnore);
		return true;
	}
	
	public static bool Install() {
		asm {
			"lidt [RAX]" : : "a"(&_idtBase);
			"sti";
		}

		Log._lockable = true; //TODO
		return true;
	}

	public static void SetInterruptGate(uint num, void* funcPtr, InterruptStackType ist = InterruptStackType.RegisterStack) {
		SetGate(num, SystemSegmentType.InterruptGate, cast(ulong)funcPtr, 0, ist);
	}
	
	public static void SetSystemGate(uint num, void* funcPtr, InterruptStackType ist = InterruptStackType.RegisterStack) {
		SetGate(num, SystemSegmentType.InterruptGate, cast(ulong)funcPtr, 3, ist);
	}

	private struct IDTBase {
	align(1):
		ushort	Limit;
		ulong	Base;
	}
	
	private struct InterruptGateDescriptor {
	align(1):
		ushort TargetLow;
		ushort Segment;
		private ushort _flags;
		ushort TargetMid;
		uint TargetHigh;
		private uint _reserved;
		
		mixin(Bitfield!(_flags, "ist", 3, "Zero0", 5, "Type", 4, "Zero1", 1, "dpl", 2, "p", 1));
	}
	
	private static void SetGate(uint num, SystemSegmentType gateType, ulong funcPtr, ushort dplFlags, ushort istFlags) {
		with (_entries[num]) {
			TargetLow = funcPtr & 0xFFFF;
			Segment = 0x08;
			ist = istFlags;
			p = true;
			dpl = dplFlags;
			Type = cast(uint)gateType;
			TargetMid = (funcPtr >> 16) & 0xFFFF;
			TargetHigh = (funcPtr >> 32);
		}
	}
	
	private static template GenerateIDT(uint numberISRs, uint idx = 0) {
		static if (numberISRs == idx)
			const char[] GenerateIDT = ``;
		else
			const char[] GenerateIDT = `SetInterruptGate(` ~ idx.stringof ~ `, &isr` ~ idx.stringof[0 .. $ - 1] ~ `);` ~ GenerateIDT!(numberISRs, idx + 1);
	}

	private static template GenerateISR(ulong num, bool needDummyError = true) {
		const char[] GenerateISR = `private static void isr` ~ num.stringof[0 .. $ - 2] ~ `(){asm{"pop RBP";` ~
			(needDummyError ? `"pushq 0";` : ``) ~ `"pushq ` ~ num.stringof[0 .. $ - 2] ~ `";"jmp %0" : : "r"(&IsrCommon);}}`;
	}
	
	private static template GenerateISRs(uint start, uint end, bool needDummyError = true) {
		static if (start > end)
			const char[] GenerateISRs = ``;
		else
			const char[] GenerateISRs = GenerateISR!(start, needDummyError)
			~ GenerateISRs!(start + 1, end, needDummyError);
	}

	pragma(msg, GenerateISR!0);
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
	//	Port.SaveSSE(Task.CurrentThread.SavedState.SSE.Data);

		Log.WriteJSON("irq", stack.IntNumber);
		Log.WriteJSON("rip", stack.RIP);
		Log.WriteJSON("rbp", stack.RBP);
		Log.WriteJSON("rsp", stack.RSP);
		/*Log.WriteJSON("cs", stack.CS);
		Log.WriteJSON("ss", stack.SS);*/
		
		/*Log.WriteJSON("gs", stack.GS);
		Log.WriteJSON("fs", stack.FS);
		Log.WriteJSON("es", stack.ES);
		Log.WriteJSON("ds", stack.DS);*/

		if (stack.IntNumber == 0xE)
			Paging.PageFaultHandler(*stack);
		else if (stack.IntNumber < 32) { //TODO: call user FaultHandler
			Log._lockable = false; //TODO
			Log.WriteJSON("interrupt", "{");
			Log.WriteJSON("irq", stack.IntNumber);
			Log.WriteJSON("rip", stack.RIP);
			Log.WriteJSON("rbp", stack.RBP);
			Log.WriteJSON("rsp", stack.RSP);
			Log.WriteJSON("cs", stack.CS);
			Log.WriteJSON("ss", stack.SS);

			Log.WriteJSON("gs", stack.GS);
			Log.WriteJSON("fs", stack.FS);
			Log.WriteJSON("es", stack.ES);
			Log.WriteJSON("ds", stack.DS);
			Log.WriteJSON("}");
			Port.Halt();

			//if (stack.IntNumber != 0x0E)
			/*	Log.WriteJSON("addr4", *(cast(ulong *)stack.RSP + 0x20));
				Log.WriteJSON("addr3", *(cast(ulong *)stack.RSP + 0x18));
				Log.WriteJSON("addr2", *(cast(ulong *)stack.RSP + 0x10));
				Log.WriteJSON("addr1", *(cast(ulong *)stack.RSP + 0x08));
				Log.WriteJSON("addr0", *(cast(ulong *)stack.RSP));*/
		}

		//if (stack.IntNumber >= 32)
		//	DeviceManager.EOI(cast(int)stack.IntNumber - 32);

		asm {
		//	"outb %%DX, %%AL" : : "d"(0x20), "a"(0x20);
		}

		//DeviceManager.Handler(*stack);
		//Port.Cli();
	//	Port.RestoreSSE(Task.CurrentThread.SavedState.SSE.Data);
	}
	
	private static void IsrIgnore() {
		asm {
			"pop RBP"; //Naked
			"nop";
			"nop";
			"nop";
			"iretq";
		}
	}
	
	extern(C) private static void IsrCommon() {
		asm {
			"pop RBP"; //Naked
			"cli";

			// Save context
			"push RAX";
			"push RBX";
			"push RCX";
			"push RDX";
			"push RSI";
			"push RDI";
			"push RBP";
			"push R8";
			"push R9";
			"push R10";
			"push R11";
			"push R12";
			"push R13";
			"push R14";
			"push R15";

			// Save segments
			"pushq GS";
			"pushq FS";
			"mov AX, ES";
			"pushq AX";
			"mov AX, DS";
			"pushq AX";
			
			// Set registers
			"mov AX, 0x10";
			"mov DS, AX";
			"mov ES, AX";
			"mov FS, AX";
			"mov GS, AX";
			
			// Run dispatcher
			"mov RDI, RSP";
			"call %0" : : "r"(&Dispatch);

			"push RAX";
			"mov RAX, 0x20";
			"outb 0x20, AL";
			"pop RAX";
			
			// Restore segments
			"popq RAX";
			"mov DS, AX";
			"popq RAX";
			"mov ES, AX";
			"popq FS";
			"popq GS";
			
			// Restore context
			"pop R15";
			"pop R14";
			"pop R13";
			"pop R12";
			"pop R11";
			"pop R10";
			"pop R9";
			"pop R8";
			"pop RDI";
			"pop RDI";
			"pop RSI";
			"pop RDX";
			"pop RCX";
			"pop RBX";
			"pop RAX";

			"add RSP, 16";
			"iretq";
		}
	}
}