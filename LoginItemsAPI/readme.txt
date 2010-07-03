Read Me About LoginItemAPI

1.0

*Description: This sample gives developers an interface into how to programatically modify the list of LoginItems on OSX.  LoginItems are applications launched each time a user logs in and are normally maintained by the "Login" System Preference.  LoginItems can be installed for specific users or for all users on the system.  Note that LoginItems are very different from startup items on OSX which are launched once and only once at system startup time.    


*What the sample does by default: There is an included main to demonstrate the use of the LoginItemAPI.  The demo setup lists the loginitems on the system, adds a login item, lists the LoginItems again, Removes the LoginItem which was added, lists the LoginItems again and then Adds the Calculator as a LoginItem before quitting.  This means at the end of the program run you will have the calculator now as a LoginItem which means it will be launched each time that user logs in.  Note all changes are done to the CurrentUsers loginitems.

The general idea is that after developers understand how to use the LoginItemAPI (likely from looking at the included demo file) they will encorparate the code for their use when they need to modify the list of LoginItems.

*Packing List:

The package contains the actual LoginItemAPI (contained in LoginItemAPI.c and LoginItemAPI.h) as well as a test source file which demonstrates how to  to add LoginItems, remove LoginItems and get a list of LoginItems.  This should be very helpful in allowing developers to easily modify the list of LoginItems.

• LoginItemAPI.c — Source to the LoginItem API.  This does all modification to the preferences as needed.
• LoginItemAPI.c — Header to the LoginItem API. 
• Testmain.c — The main file in the program and a demonstration file showing how to add, remove and list the loginitems on the system.       
• LoginItemAPI.pbproj — The project builder project file.
• LoginItemAPI.mcp - The CodeWarrior project file.  Both projects make use of the same source files.
• LoginItemAPIPrebuilt — An included executable file in case you want to run the program without actually building it.  This file is actually a copy of what Codewarrior gives you upon a successful build.

*Sample Requirements:

For ProjectBuilder users: This project was built with ProjectBuilder version 1.0 as a standard tool.  The project relys on the CoreFoundation framework.

For CodeWarrior users: This project was built with CodeWarrior IDE version 4.2 as a Carbonized Application.  The project relys on Carbon lib and was built using the CarbonLib 1.2.5 headers.

*Running the Sample:

To run the sample without building it simply double click the LoginItemAPIPrebuilt file within OSX.  This will launch the executable demo file which does the same thing a built sample will do.  See the "What the sample does by default" section above for an exact description of what running the executable does.

*Building the Sample:

Using Project Builder:  To build the sample simply open the Project builder file associated with that individual sample (LoginItemAPI.pbproj) and hit the 'build' button.  Similary the sample can be run simply by clicking the 'run' button.

Using CodeWarrior: To build the sample simply open the CodeWarrior project file (LoginItemAPI.mcp) and select 'make'.  Similarly the sample can be run by selecting the 'run' option.

*Credits and Version History:

If you find any problems with this sample or have any suggestions, mail <dts@apple.com> with “Attn: Chad Jones” as the first line of your mail.

Version 1.0 is the first release.

Chad Jones
Apple Developer Technical Support
Networking, Communications, Hardware

July 19, 2001
