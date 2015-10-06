/**
 * Copyright (c) 2014-2015 Trinix Foundation. All rights reserved.
 * 
 * This file is part of Trinix Operating System and is released under Trinix 
 * Public Source Licence Version 1.0 (the 'Licence'). You may not use this file
 * except in compliance with the License. The rights granted to you under the
 * License may not be used to create, or enable the creation or redistribution
 * of, unlawful or unlicensed copies of an Trinix operating system, or to
 * circumvent, violate, or enable the circumvention or violation of, any terms
 * of an Trinix operating system software license agreement.
 * 
 * You may obtain a copy of the License at
 * https://github.com/Bloodmanovski/Trinix and read it before using this file.
 * 
 * The Original Code and all software distributed under the License are
 * distributed on an 'AS IS' basis, WITHOUT WARRANTIES OR CONDITIONS OF ANY 
 * KIND, either express or implied. See the License for the specific language
 * governing permissions and limitations under the License.
 * 
 * Contributors:
 *      Matsumoto Satoshi <satoshi@gshost.eu>
 */

module System.FileHandle;

import System.Runtime;


class FileHandle : SafeHandle {
    private enum IDENTIFIER = "com.trinix.VFSManager.FSNode";
	
	enum StaticCommands {
		Create,
		Open
	}
	
	private this() {
	
	}

    static FileHandle CreateFile(string fileName) {
        return Create!FileHandle(IDENTIFIER, StaticSyscall("com.trinix.VFSManager", StaticCommands.Create, cast(long)fileName.ptr, FileType.File));
    }

    alias FileAttributes = int;
    FileAttributes Attributes() {
        static const auto getAttribs = SafeMethodCall("com.trinix.VFSManager.FSNode.GetAttributes");

        FileAttributes attribs;
        if (getAttribs.Call(cast(long)&attribs) == SyscallReturn.Error)
            return null;

        return attribs;
    }
}