// Build using: dotnet publish -c Release
using System;
using System.Reflection;
using System.Runtime.InteropServices;

namespace HelloWorld
{
    class helloWorld
    {
        static void Main(string[] args)
        {
            string banner = @"
                               /T /I
                              / |/ | .-~/
                          T\ Y  I  |/  /  _
         /T               | \I  |  I  Y.-~/
        I l   /I       T\ |  |  l  |  T  /
     T\ |  \ Y l  /T   | \I  l   \ `  l Y
 __  | \l   \l  \I l __l  l   \   `  _. |
 \ ~-l  `\   `\  \  \\ ~\  \   `. .-~   |
  \   ~-. """"-. `  \  ^._ ^. """"-. /  \   |
.--~-._  ~-  `  _  ~-_.-""""-."" ._ /._ ."" ./
 >--.  ~-.   ._  ~>-""    ""\\   7   7   ]
^.___~""--._    ~-{  .-~ .  `\ Y . /    |
 <__ ~""-.  ~       /_/   \   \I  Y   : |
   ^-.__           ~(_/   \   >._:   | l______
       ^--.,___.-~""  /_/   !  `-.~""--l_ /     ~""-.
              (_/ .  ~(   /'     ~""--,Y   -=b-. _)
               (_/ .  \  :           / l      c""~o \
                \ /    `.    .     .^   \_.-~""~--.  )
                 (_/ .   `  /     /       !       )/
                  / / _.   '.   .':      /        '
                  ~(_/ .   /    _  `  .-<_
                    /_/ . ' .-~"" `.  / \  \          ,z=.
                    ~( /   '  :   | K   ""-~-.______//
                      """"-,.    l   I/ \_    __{--->._(==.
                       //(     \  <    ~""~""     //
                      /' /\     \  \     ,v=.  ((
                    .^. / /\     ""  }__ //===-  `
                   / / ' '  """"-.,__ {---(==-
                 .^ '       :  T  ~""   ll       
                / .  .  . : | :!        \\
               (_/  /   | | j-""          ~^
                 ~-<_(_.^-~""

With words, man surpasses animals, but with silence he surpasses himself. 

 _   _ _           _   _                _    
| \ | (_)_ __ ___ | | | | __ ___      _| | __
|  \| | | '_ ` _ \| |_| |/ _` \ \ /\ / / |/ /
| |\  | | | | | | |  _  | (_| |\ V  V /|   < 
|_| \_|_|_| |_| |_|_| |_|\__,_| \_/\_/ |_|\_\

";
            try 
            {
                Console.WriteLine(banner);
                 // Runtime information
                Console.WriteLine("=== Nimhawk .NET Assembly Test ===");
                Console.WriteLine($"Time: {DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss")}");
                
                // Basic runtime info (minimal API calls)
                Console.WriteLine("\n[Basic Info]");
                Console.WriteLine($"  Running in 64-bit process: {Environment.Is64BitProcess}");
                Console.WriteLine($"  Framework: {Environment.Version}");
                
                // User context - basic information
                Console.WriteLine("\n[User]");
                Console.WriteLine($"  Username: {Environment.UserName}");
                
                // Arguments - simple display
                Console.WriteLine("\n[Arguments]");
                if (args.Length > 0)
                {
                    for (int i = 0; i < args.Length; i++)
                    {
                        Console.WriteLine($"  [{i}]: {args[i]}");
                    }
                }
                else
                {
                    Console.WriteLine("  None provided");
                }
            }
            catch (Exception ex)
            {
                // Minimal error reporting
                Console.WriteLine($"Error: {ex.Message}");
            }
        }
    }
}