# Compile with: x86_64-w64-mingw32-gcc -c bof.c -o message-box.o -w
#include <windows.h>
#include <stdio.h>
#include "beacon.h"

WINUSERAPI int WINAPI USER32$MessageBoxA(HWND hWnd,LPCSTR lpText,LPCSTR lpCaption,UINT uType);
WINBASEAPI DWORD WINAPI KERNEL32$GetLastError(void);

int go(char * args, unsigned long len) {

   BeaconPrintf(CALLBACK_OUTPUT, "Executing MessageBoxA on the target machine\n");
   int result = USER32$MessageBoxA(NULL, "Thank you for joining 100 Days of Red Team." , "MessageBox BOF", MB_ICONINFORMATION | MB_OKCANCEL);
   
   if ( result ==0 ) {
      BeaconPrintf(CALLBACK_ERROR, "Could not execute MessageBoxA. Encountered error: %d",KERNEL32$GetLastError());
   }
   else {
      BeaconPrintf(CALLBACK_OUTPUT, "Successfully executed MessageBoxA on the target machine.\n");
   }
   
   return 0;
}
