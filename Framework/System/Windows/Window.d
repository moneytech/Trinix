module System.Windows.Window;

import System.IO.FileStream;
import System.IO.Directory;
import Userspace.Libs.Graphics;
import System.Collections.Generic.List;
import System.Diagnostics.Process;
import System.Convert;


abstract class Window {
protected:
	Graphics ctx;
	static __gshared ProcessWindows pwins;
	static __gshared Window ths;

	FileStream eventPipe;
	FileStream mouseEventPipe;

	public ushort Width, Height;
	public byte[] Buffer; //shared buffer with compositor

	ulong id; //id of this instance in compositor
	ubyte crcvd; //TODO: updatovat...


public:
	static const PACKET_MAGIC = 0x12345689;

	enum Commands : ubyte {
		NewWindow,
		Resize,
		Destroy,
		Damage,
		Redraw,
		Reorder,
		SetAlpha
	}

	enum Events : ubyte {
		KeyDown       = 0x10,
		KeyUp         = 0x11,
		MouseMove     = 0x20,
		MouseEnter    = 0x21,
		MouseLeave    = 0x22,
		MouseClick    = 0x23,
		MouseUp       = 0x24,
		WindowNew     = 0x30,
		WindowResized = 0x31,
		WindowsClosed = 0x32,
		WindowRedrawn = 0x33,
		WindowsFocus  = 0x34,

		/** Groups */
		GroupMask     = 0xF0,
		KeyEvent      = 0x10,
		MouseEvent    = 0x20,
		WindowEvent   = 0x30
	}


	/** Struktura okien kazdeho procesu jak na strane klienta tak na strane kompozitoru */
	struct ProcessWindows {
		Process ID;
		FileStream EventPipe;
		FileStream CommandPipe;
		List!byte Windows;
	}

	/** Hlavicka kazdeho packetu pre command alebo enevt */
	struct PacketHeader {
		uint Magic;
		ubyte CommandType;	/* Command or event specifier */
		ulong PacketSize;	/* Size of the *remaining* packet data */
	}

	struct WWindow {
		ulong ID;      /* or none for new window */
		short Left;    /* X coordinate */
		short Top;     /* Y coordinate */
		ushort Width;  /* Width of window or region */
		ushort Height; /* Height of window or region */
	//	ubyte Command; /* The command (duplicated) */
	}


	this() {
		//connect root process
		if (pwins.Windows is null) {
			pwins.Windows     = new List!byte();
			pwins.EventPipe   = Directory.CreatePipe();
			pwins.CommandPipe = Directory.CreatePipe();
			
			auto curProc      = Process.Current;
			auto compositor   = new FileStream("/dev/compositor");

			long[3] tmp = [curProc.ResID(), pwins.EventPipe.ResID(), pwins.CommandPipe.ResID()];
			compositor.Write(Convert.ToByteArray(tmp), 0);

			byte[8] id;
			pwins.EventPipe.Read(id, 0);
			pwins.ID = new Process(Convert.ToInt64Array(id)[0]);

			curProc.SetSignalHanlder(SigNum.SIGWINEVENT, &SignalEvent);
		}

		eventPipe      = Directory.CreatePipe();
		mouseEventPipe = Directory.CreatePipe();
	}

	void Show() {
		SendCommand(100, 100, Width, Height, Commands.NewWindow, true);

		ctx = new Graphics(this);
		ctx.Fill(0xFFFFFF);
		FormStyle.RenderDecorationSimple(this, true);
		ctx.Flip();
	}


private:
	void SignalEvent() {
		ulong len = pwins.EventPipe.Length;
		do {
			ProcessEvent();
			len = pwins.EventPipe.Length;
		} while (len);
	}

	void ProcessEvent() {
		PacketHeader header;
		pwins.EventPipe.Read(Convert.ObjectToByteArray(header), 0);

		if (header.Magic != PACKET_MAGIC && pwins.EventPipe.Length) {
			byte[0x256] tresh;
			pwins.EventPipe.Read(tresh, 0);
		}

		switch (header.CommandType & Events.GroupMask) {
			case Events.MouseEvent:
			case Events.KeyEvent:
			case Events.WindowEvent:
			default:
				break;
		}
	}

	void SendCommand(short left, short top, ushort width, ushort height, Commands command, bool waitForReply = false) {
		PacketHeader header;
		header.Magic = PACKET_MAGIC;
		header.CommandType = command;
		header.PacketSize = WWindow.sizeof;

		WWindow packet;
		packet.ID     = id;
		packet.Left   = left;
		packet.Top    = top;
		packet.Width  = width;
		packet.Height = height;

		pwins.CommandPipe.Write(Convert.ObjectToByteArray(header), 0);
		pwins.CommandPipe.Write(Convert.ObjectToByteArray(packet), 0);

		if (waitForReply) {
			Process cur = Process.Current;
			crcvd = cast(byte)(command + 1);
			pwins.ID.SendSignal(SigNum.SIGWINEVENT);

			while ((crcvd & 0x0F) != (command & 0x0F))
				cur.Switch();
		}
	}


	class FormStyle {
	static:
		void RenderDecorationSimple(Window win, bool focused = false) {
			foreach (i; 0 .. win.Height) {
				win.ctx.Pixel(0, i) = 0x3E3E3E;
				win.ctx.Pixel(win.Width - 1, i) = 0x3E3E3E;
			}

			foreach (i; 1 .. 24) {
				foreach (j; 1 .. win.Width - 1) {
					win.ctx.Pixel(j, i) = focused ? 0x00A2E8 : 0xB4B4B4;
				}
			}

			foreach (i; 0 .. win.Width) {
				win.ctx.Pixel(i, 0) = 0x3E3E3E;
				win.ctx.Pixel(i, 24 - 1) = 0x3E3E3E;
				win.ctx.Pixel(i, win.Height - 1) = 0x3E3E3E;
			}
		}
	}
}