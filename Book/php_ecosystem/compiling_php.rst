.. _compiling_php:

Compiling PHP from sources
==========================

Recall on compilation
---------------------

From what you know or learnt reading our {link}prerequisites chapter{link}, it's now the moment to turn PHP's source code to machine instructions and build the program so that it will run on your platform.
This chapter focuses on PHP mainly, and we don't know anything about your system, except we assume it is supported by PHP. Remind that this book takes as example Linux based platforms, mainly Debian. We assume you master you system.
Should you really know your hardware and your system, you would use any custom compiler, compiler module or extension, as well as any compiler special switch. We'll here use default ones, but show you some cool stuff coming from the *GCC* compilation tool.

Getting sources and dependencies ready
--------------------------------------

There exists two different ways to grab PHP original source code : from packages we provide behind http://download.php.net , this is usually what you'll do. The other way is to check out the source code directly from our git repository, located at http://git.php.net (mirrored on Github, at http://www.github.com/php-src).
Those two ways differ a little bit when comes the time to compile PHP. Here are what we can say about them :

    * PHP coming from git doesn't bundle a default configure script, you will have to generate it, so you'll need to run our ``buildconf`` script, which itself relies on the autotools suite you'll have to install if not done yet.
    * PHP coming from git doesn't bundle generated lexer and parser, you'll have to build them, so you'll need re2c and bison tools.

Basically, a PHP source coming from our packages is just ready to be built but a PHP source coming from a checkout of any branch from git will need more tools to get those sources prepared for compilation.

First look at the configure script
**********************************

.. code-block:: none

    > mkdir /tmp/phpsrc && cd /tmp/phpsrc
    /tmp/phpsrc> wget http://us.php.net/get/php-5.4.15.tar.gz/from/this/mirror
    /tmp/phpsrc> tar xzf php-5.4.15.tar.gz && cd php-5.4.15
    /tmp/phpsrc/php-5.4.15> ls -al
    
There we downloaded PHP from one of our mirror, unpacked it and browsed the files. We can see a configure script, let's now run it.

.. note::

    Remember that if you get PHP from git, the configure script is not present in the tree. You should then run the buildconf.sh script which will invoke the autotools chain, mainly parsing the .m4 templates and generate a configure script for you. Starting from PHP 5.4, we support autoconf 2.59, notice that before PHP5.4, only autoconf 2.13 is supported.
    
.. code-block:: none

    /tmp/phpsrc/php-5.4.15> ./configure --help | less
    
Here you can see all the switches we provide to set up PHP. There are many of them, and we assume you are used to running the configure script, so we won't (and can't) detail all the options you would be able to use.
Remember that dependi  ng on the version of PHP you use, those switches may differ. For example, we bundle different extensions in different PHP versions setups.

Let's prepare for a default installation :

.. code-block:: none

    /tmp/phpsrc/php-5.4.15> ./configure --prefix=/home/myuser/myphp
    
Depending on you system, the configure script ends up with an error saying that some libraries are missing. By default, when you want to compile PHP, XML support is enabled, and we need libxml2 to provide such a support. Usually the header files for this lib are not installed and configure cannot continue. It may also be the case for other required libraries. Read the output of configure script, and download all the libraries needed, as well as their header files (usually provided by a *"-dev"* package from you package manager tool).

.. note::

    It even can happen that no compiling suite is found on your system by default. A C compiler is needed to build PHP, as well as a C++ compiler, a C preprocessor and a linker. If you rely on Unix and GNU tools, usually the *GCC* suite provides all you need about that.
    On Debian based systems, the *build-essential* package provides all tools needed to compile software for you system, it is then a good choice to have it installed.

Just running configure script out of the box will prepare PHP sources to be compiled by checking that your system provides all dependencies PHP needs. Once done, it should end successfully with something like :

.. code-block:: none

    Generating files
    configure: creating ./config.status
    creating main/internal_functions.c
    creating main/internal_functions_cli.c
    +--------------------------------------------------------------------+
    | License:                                                           |
    | This software is subject to the PHP License, available in this     |
    | distribution in the file LICENSE.  By continuing this installation |
    | process, you are bound by the terms of this license agreement.     |
    | If you do not agree with the terms of this license, you must abort |
    | the installation process at this point.                            |
    +--------------------------------------------------------------------+

    Thank you for using PHP.

    config.status: creating php5.spec
    config.status: creating main/build-defs.h
    config.status: creating scripts/phpize
    config.status: creating scripts/man1/phpize.1
    config.status: creating scripts/php-config
    config.status: creating scripts/man1/php-config.1
    config.status: creating sapi/cli/php.1
    config.status: creating main/php_config.h
    config.status: executing default commands

Huray, sources are now ready to be compiled.

Let's make and install it !
---------------------------

Once your sources are ready, you now have to compile them all. As PHP relies on autotools and make to get compiled, all you have to do now is run the ``make`` tool, and, that's it !

.. code-block:: none

    /tmp/phpsrc/php-5.4.15> make
    
make should end successfully, with something like :

.. code-block:: none

    Build complete.
    Don't forget to run 'make test'
    
It encourages you to run the ``make test`` command. This command will run the *test* target from the ``MakeFile`` file, which will run the freshly-built PHP binary against our test suite, located into the different *tests/* directories of the PHP source tree.
Nowadays, we provide by default about 9000 tests, and unfortunately the tests are not run in parallel yet, thus the ``make test`` command can take up to 5min to complete, depending on your hardware.

If this is the first time you compile PHP on your platform, we encourage you to run the test suite. Depending on your OS, your environment and most of all : your hardware and your compiler, you may find bugs in PHP by running the test suite. The good new is that all is autommated, at the end of the test suite run, the script will ask you if you want to send the report. If you say yes, a report will be uploaded to our qa platform, and it can be analyzed by our automates or our contributors later on. Thank you for this free and easy step :-)

.. note::

    If you are experiencing problems compiling PHP, we provide a help paragraph at the end of this chapter.
    
PHP is compiled, now it is time to install it :

.. code-block:: none

    /tmp/phpsrc/php-5.4.15> make install

The compiled files will be installed in the directory you provided to the ``--prefix`` switch of the configure script. For a try, it is usually a good idea to store the installed files somewhere behind your home directory. As an example, we used */home/myuser/myphp*

.. note::

    You will have noticed that you should customize this directory ( */home/myuser/myphp* ) and make it fit your user account or your needs.

Check all is right
******************

Let's have a look at the default install tree :

.. code-block:: none

    > tree -L 3 /home/myuser/myphp

    /home/myuser/myphp
    |-- bin
    |   |-- pear
    |   |-- peardev
    |   |-- pecl
    |   |-- phar -> /tmp/myphp/bin/phar.phar
    |   |-- phar.phar
    |   |-- php
    |   |-- php-cgi
    |   |-- php-config
    |   `-- phpize
    |-- etc
    |   `-- pear.conf
    |-- include
    |   `-- php
    |       |-- ext
    |       |-- include
    |       |-- main
    |       |-- sapi
    |       |-- TSRM
    |       `-- Zend
    |-- lib
    |   `-- php
    |       |-- Archive
    |       |-- build
    |       |-- Console
    |       |-- data
    |       |-- doc
    |       |-- OS
    |       |-- PEAR
    |       |-- PEAR5.php
    |       |-- pearcmd.php
    |       |-- PEAR.php
    |       |-- peclcmd.php
    |       |-- Structures
    |       |-- System.php
    |       |-- test
    |       `-- XML
    `-- php
        `-- man
            `-- man1

Quick tour :

    * *bin/* contains obviously binaries. The most important is the CLI PHP : *bin/php*
    * *etc/* contains obviously configuration. Note that the default php.ini directory is *not* here
    * *include/php* contains header files which will be needed if you want to further build extensions or embed any part of PHP to a custom software
    * *lib/php* contains PEAR default files. It is also the default php.ini directory and the default extensions directory
    * *php/man* obviously contains man pages for the ``php`` command.
    
.. note ::

    If you don't provide a ``--prefix`` switch to your *configure* command, default location is ``/usr/local``. PHP'll then be merged to the ``/usr/local`` tree, which is all right and respects the {link}Linux Standard Directory Structure{link}
    If you want to build several versions of PHP, the easiest way is to customize the place they'll be installed in, by playing with the *--prefix* configure switch. Each installation directory is totally independant from each other.

Now let's check our binary against several switches to see what to expect from it :

.. code-block:: none

    ~/myphp> cd bin
    ~/myphp/bin> ./php -v
    PHP 5.4.15 (cli) (built: Jun 13 2013 12:24:03)
    Copyright (c) 1997-2013 The PHP Group
    Zend Engine v2.4.0, Copyright (c) 1998-2013 Zend Technologies

Ok, this is our PHP.

.. code-block:: none

    ~/myphp/bin> ./php -m
    [PHP Modules]
    Core
    ctype
    date
    dom
    ereg
    fileinfo
    filter
    hash
    iconv
    json
    libxml
    pcre
    PDO
    pdo_sqlite
    Phar
    posix
    Reflection
    session
    SimpleXML
    SPL
    sqlite3
    standard
    tokenizer
    xml
    xmlreader
    xmlwriter

    [Zend Modules]

Here you can see a list of the default extensions which are activated if you don't touch anything about the configure script.
Default activated extensions may vary upon the PHP version you compile.

.. code-block:: none
    
    ~/myphp/bin> ./php --ini
    Configuration File (php.ini) Path: /tmp/myphp/lib
    Loaded Configuration File:         (none)
    Scan for additional .ini files in: (none)
    Additional .ini files parsed:      (none)

Interesting here. Against what you could expect, PHP wont look for a *php.ini* configuration file in its own *etc/* directory, but in its *lib/* directory. And you also can notice that, by default, no *php.ini* is provided.
There exists two *php.ini* into the source directory, it is your responsability to use them if you want, so you have to copy them on your own. You could also use a custom *php.ini* you write from scratch.

.. code-block:: none
    
    ~/myphp/bin> cp /tmp/phpsrc/php-5.4.15/php.ini-development ~/myphp/lib/php.ini
    ~/myphp/bin> ./php --ini
    Configuration File (php.ini) Path: /tmp/myphp/lib
    Loaded Configuration File:         /tmp/myphp/lib/php.ini
    Scan for additional .ini files in: (none)
    Additional .ini files parsed:      (none)

Here we just copied a default *php.ini* in the default directory and confirmed that PHP now really uses it.

.. note::

    You can customize the *php.ini* path, as well as *"additional .ini files"*. We show you all that in a paragraph later in this chapter.
    We'd like to remind you as well that PHP not necessarily looks for a *"php.ini"* file, it also looks for a *"php-{sapi name}.ini"* file. The name of the ini file can be customized depending on the SAPI, so, for a CLI PHP, you could use a *php-cli.ini*, and for the CGI PHP, a *php-cgi.ini*. This is interesting as PHP generally should behaves differently depending on the SAPI it is run from. Linux distribution packages usually rely on such a feature to build flexible trees of PHP installations.

.. code-block:: none
    
    ~/myphp/bin> ldd ./php
    linux-vdso.so.1 =>  (0x00007fff0adff000)
	libcrypt.so.1 => /lib/x86_64-linux-gnu/libcrypt.so.1 (0x00007f9689077000)
	libresolv.so.2 => /lib/x86_64-linux-gnu/libresolv.so.2 (0x00007f9688e61000)
	librt.so.1 => /lib/x86_64-linux-gnu/librt.so.1 (0x00007f9688c58000)
	libm.so.6 => /lib/x86_64-linux-gnu/libm.so.6 (0x00007f96889d6000)
	libdl.so.2 => /lib/x86_64-linux-gnu/libdl.so.2 (0x00007f96887d2000)
	libnsl.so.1 => /lib/x86_64-linux-gnu/libnsl.so.1 (0x00007f96885b9000)
	libxml2.so.2 => /usr/lib/x86_64-linux-gnu/libxml2.so.2 (0x00007f9688457000)
	libc.so.6 => /lib/x86_64-linux-gnu/libc.so.6 (0x00007f96880cd000)
	libpthread.so.0 => /lib/x86_64-linux-gnu/libpthread.so.0 (0x00007f9687eb0000)
	/lib64/ld-linux-x86-64.so.2 (0x00007f96892d2000)
	libz.so.1 => /lib/x86_64-linux-gnu/libz.so.1 (0x00007f9687c99000)
	liblzma.so.5 => /lib/x86_64-linux-gnu/liblzma.so.5 (0x00007f9687a76000)

Here we checked the dependencies of this PHP build against the system libraries. By default, with a default ``./configure`` command, some extensions get compiled, and those, as well as PHP Core, need dynamic shared libraries to work.
If you dont know what shared libraries are and what they provide, please, check our chapter about {link}prerequisites{link}

PHP tools provided with installation
------------------------------------

Until now, we talked about the PHP binary. But the bin/ directory created by the setup not only contains the PHP binary. It contains also usefull binaries or scripts, which will be needed for later extension compilation.
Extensions are treated in their own chapter, here, we'll present tools that help building them.

phpize
******

``make install`` creates by default a *bin/phpize* file. This is a shell script which is responsible for importing the PHP files to an extension directory in order to further prepare it, compile it and install it.
We will talk again about this file in the extension dedicated chapter. What important thing you should know is that this file is really tied to this *particular PHP setup*, and will be needed if you further want to build extensions for *this particular PHP setup*.

To have an idea, *phpize* is a shell script, so, go and watch its source. It's trivial to read and understand.

php-config
**********

In the installed *bin/* directory, you can also find another important file called php-config. This is an executable shell script you can run.
Let's go for it :

.. code-block:: none

    ~/myphp/bin> php-config
    Usage: ~/myphp/bin/php-config [OPTION]
    Options:
      --prefix            [/home/myuser/myphp/bin/myphp]
      --includes          [-I/home/myuser/myphp/include/php -I/home/myuser/myphp/include/php/main -I/home/myuser/myphp/include/php/TSRM -I/home/myuser/myphp/include/php/Zend -I/home/myuser/myphp/include/php/ext -I/home/myuser/myphp/include/php/ext/date/lib]
      --ldflags           []
      --libs              [-lcrypt   -lresolv -lcrypt -lrt -lrt -lm -ldl -lnsl  -lxml2 -lxml2 -lxml2 -lcrypt -lxml2 -lxml2 -lxml2 -lcrypt ]
      --extension-dir     [/home/myuser/myphp/lib/php/extensions/debug-non-zts-20100525]
      --include-dir       [/home/myuser/myphp/include/php]
      --man-dir           [/home/myuser/myphp/php/man]
      --php-binary        [/home/myuser/myphp/bin/php]
      --php-sapis         [ cli cgi]
      --configure-options [--prefix=/home/myuser/myphp --enable-debug]
      --version           [5.4.16-dev]
      --vernum            [50416]

This script is a *pkg-config* like script. It is aimed to be invoked by the compiler when compiling future extensions for this PHP build. You usually provide its path to the configure script of any extension.
Appart from that, this script has two important options you could need further in your development : it recalls you about the default extension directory of this PHP build, as well as the configure options which were used to build this particular PHP.
Those informations can also be extracted from ``phpinfo()`` call, though this is little bit cumbersome as the outpout of ``phpinfo()`` will have to be parsed. *php-config* directly gives usefull informations about the PHP setup.

.. note::

    If you are not used to the *pkg-config* tool, it could be interesting you grab more informations about it using your favorite search engine. That way you will fully understand the usage of *php-config*.

Customizing PHP compilation
---------------------------

We know how to compile PHP. We'll now concentrate on particular *./configure* switches aimed to customize many things in the PHP setup. Just invoking the configure script without any option leads to a default PHP install.
Let's now customize it.

.. note::

    It's both impossible and useless to detail all the *configure* script options. Most of them are taken from default *autoconf* configuration. We encourage you to learn more about *autoconf* and *autotools* if you are not familiar with them. This will help you understand lots of *configure* options.

Interesting configure switches
******************************

If you just need to test very basic feature of PHP, you could provide the *--disable-all* switch, which disable all non-needed extensions.
Turning on this switch activates all the --disable possible switches, thus ending, if no more --enable switches were used, in a very tiny PHP binary, having a low memory footprint, but also having far less embeded features.
Running some stuff against a tiny PHP, just to show :

.. code-block:: none

    > /path/to/tinyphp/bin/php -m 
    Core
    date
    ereg
    pcre
    Reflection
    SPL
    standard

Those extensions are the minimum required ones, we talk about them deeper in the dedicated chapter about extensions.

.. warning::

    A "tiny" PHP, compiled with just *--disable-all* switch, is often useless : no XML support at all, not even sessions. This is just a version you could use if you dont want the compilation to last too much (as it is very little, very few files get compiled, thus a minimal compilation time) or if you just need very basic PHP features (strings, array, functions and that's nearly all) with little memory footprint.

You have lots of switches to activate extensions mainly. We won't talk about all of them, but *--with-libedit* or *--with-libreadline* let you build a PHP with a nice interactive mode looking like a REPL (Read Eval Print Loop). You launch it using *-a* switch on the PHP binary, like this:

.. code-block:: none

    >/path/to/php/bin/php -a
    Interactive shell

    php > $a = "foo";
    php > var_dump($a);
    string(3) "foo"
    php > $b = 3; $c = 8;
    php > echo $b+$c;
    11
    php > 

Finally we have to talk about this crucial switch you use whenever you develop in PHP source code or you write an extension : the *--enable-debug* switch. It tells the building suite to make a debug version of PHP. If you read the source, it's all about ``#ifdef ZEND_DEBUG`` macros.
You recognize a PHP with debug switch in several ways :

    * Just ask for php -v output, it will clearly show "DEBUG"
    * Invoke *php-config --configure-options* and grep "debug"

What should be known about debug mode is that the extensions must be built with debug mode as well to work. It even happens that the default extensions directory name is built with the debug flag into it :

    * For a PHP compiled with debug flag : *lib/php/extensions/debug-non-zts-20100525*
    * For a PHP compiled without debug flag : *lib/php/extensions/no-debug-non-zts-20100525*
    
.. warning::

    You cannot not run extensions compiled for a no-debug PHP on a PHP compiled with debug flag, and vice-versa. Even if this is the exact same version of PHP : you have to recompile the extensions in debug mode.
    
Also, never run a debug build of PHP in production mode.

.. warning::

    Never run a debug build of PHP in production.
    
Seriously, the debug flag slows down PHP execution in so many ways. That's normal, debug adds many more checks everywhere in the C code, structures are usually heavier thus leading to a bigger memory footprint as well.
Also, enabling debug automatically turns off every compiler optimisation passes, which for GCC means invoking it with the *-O0* flag.

make options
************

If you know make, then it's OK. If not, we recommand you to use the *-j* flag which basically tells make to run compilation in parallel, distributing compilation tasks on several CPUs / Cores. Use it with the number of Cores you have on your machine.

.. code-block:: none

    > grep "cpu cores" /proc/cpuinfo
    cpu cores     4
    path/to/phpsrc > make -j4

If you happen to compile PHP with lots of extensions activated, the time taken to compile can grow up to several minutes on modern hardware, thus the *-j make* flag is very usefull.

Providing additionnal C compiler options
****************************************

*Make* also let you pass options to the compiler it'll use, by providing the CFLAGS variable.
With PHP, you cant pass them directly to *make* as libtool is used and just ignores them. Better pass them to your configure script.

Should you want to experiment performance flags of GCC, you could use, for example :

.. code-block:: none

    src/> CFLAGS="-O4 -march=native" ./configure && make
    
Those two GCC flags will tell it to compile the files with the maximum optimization level, and to produce machine code for the actual CPU (native architecture), which, depending on your hardware, can give a performance boost to the resulting PHP.

.. warning ::

    Master your compiler and your architecture if you come to play with GCC optimization level and flags. If you dont, you can end up with a PHP randomly crashing. We dont really support high level of optimization in PHP source code, we support the default -O2 level. But if know what you talk about, go for it.
    
.. note::

    Perhaps reading http://gcc.gnu.org/onlinedocs/gcc/Optimize-Options.html may help here. You'll find lots of information about GCC flags.

Compilation usual problems
--------------------------

As you may know, *make* makes a cache of all the objects it builds, so that its next invocations will be much faster. If you change just one C source file and run *make* again, it should guess this and only compile the dedicated object, then tries to link again and end out with the final build.
But, sometimes, this just does not work well. If you experience strange errors in *make* output, and have invoked *make* several times before, think about running *make clean*, which will delete all the compiled objects so that the next *make* call starts the compilation back from the beginning on a clean basis.

Also, if you play with *configure* options and change them before invoking *make*, better as well to run* make clean* before *make*.

There also exists a *make* target called *"distclean"*, which is a normal clean, but it also rolls back all the stuff brought by the *./configure* command invocation (it deletes configure caches, as well as the *Makefile* and other temporary files).
In short, remember *make distclean* as beeing a total cleanup of anything created or modified by previous *configure* or *make* calls.

If you use PHP sources from git, or if you modify m4 files (we talk about such files in the extensions dedicated chapter), then you always have to rebuild the configure script.
If you dont, you'll meet errors at compilation, for sure, because you invoke *configure* so that it will prepare files based on an old API you modified. *configure* has no way to guess new C files to prepare for compilation or new checks to perform : you must rebuild the configure script.
This is done by deleting the configure script and running the buildconf script, usually with the "force" switch :

.. code-block:: none

    > rm configure
    > ./buildconf --force
    Forcing buildconf
    Removing configure caches
    buildconf: checking installation...
    buildconf: autoconf version 2.69 (ok)
    rebuilding aclocal.m4
    rebuilding configure
    rebuilding main/php_config.h.in
    
.. warning::

    Think about deleting the configure script before invoking the buildconf script.
