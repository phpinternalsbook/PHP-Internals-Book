Debugging with GDB
==================

This chapter will introduce you with the GNU C debugger, aka GDB. When a crash happens, you usually have to find the
guilty part in thousands of lines. You need tools for that, and GDB is the most commonly used debugger under Unix
platforms. Here we'll give you an introduction to GDB and how to practice with it against the PHP source code.

Debug symbols
-------------

GDB requires debug symbols to map the memory addresses in your binary to the original position in your source code. To
generate debug symbols you need to pass the ``--enable-debug`` flag to the ``./configure`` script. To get even more
debugging information you may add the ``CFLAGS="-ggdb3"`` flag which will add support for macros.
