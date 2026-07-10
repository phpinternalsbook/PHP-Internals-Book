Prerequisites
=============

The following is list of prerequisites and assumptions needed for writing
a PDO database driver:
 
#. A working target database, examples, demos, etc. working as per vendor
   specifications

#. A working development environment:

   * Linux: standard development tools, gcc, ld, make, autoconf, automake, etc., versions dependent on distribution
   * Other Unix: standard development tools supplied by vendor plus the GNU development tool set
   * Win32: Visual Studio compiler suite

#. A working PHP environment version 5.0.3 or higher with a working PEAR extension version 1.3.5 or higher
#. A working PDO environment (can be installed using 'sudo pecl install PDO'), including the headers
   which will be needed to access the PDO type definitions and function declarations
#. A good working knowledge of the C programming language
#. A good working knowledge of the way to write a PHP extension; George Schlossnagle's*
   **Advanced PHP Programming** (published by Developer's Library, chapters 21 and 22) is recommended
#. Finally, a familiarity with the Zend API that forms the heart of PHP, in
   particular paying attention to the memory management aspects.
