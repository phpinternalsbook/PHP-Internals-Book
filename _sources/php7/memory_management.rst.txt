Memory management
=================

C programmers usually have to deal with memory by hand. With dynamic memory, the programmer allocates memory when
needing and frees it when finished. Failing to free dynamic memory leads to a "memory leak", which may or may not be a
bad thing. In the case of PHP, as the process could live for a virtually infinite amount of time, creating a memory leak
will be dramatic. In any situation, leaking memory really translates to poorly and badly designed programs that cannot
be trusted.
Memory leaking is easy to understand. You ask the OS to book some part of the main machine memory for you, but you never
tell it to release it back for other processes usage : you are not alone on the machine, other processes need some
memory, and the OS itself as well.

Also, in C, memory areas are clearly bound. Reading or writing before or after the bounds is a very nasty operation.
That will lead for sure to a crash, or worse an exploitable security issue. There are no magical things like
auto-resizeable areas with the C language. You must clearly tell the machine (and the CPU) what you want it to do. No
guess, no magic, no automation of any kind (like garbage collection).

PHP's got a very specific memory model, and provides its own layer over the traditional libc's dynamic memory
allocator. This layer is called **Zend Memory Manager**.

This chapter explains you what Zend Memory Manager is, how you must use it, and what you must/must not do with it.
After that, we'll quickly introduce you to specific tools used in the C area to debug dynamic memory.

.. note:: If you need, please get some (possibly strong) knowledge about C memory allocation classes (static vs
          dynamic memory), and about libc's allocator.

Contents:

.. toctree::
    :maxdepth: 2

    memory_management/zend_memory_manager.rst
    memory_management/memory_debugging.rst
