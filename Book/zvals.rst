Zend variables : zvals
======================

Now that we know how to manage the memory into PHP source code, let’s see how we
can create PHP variables from an internals point of view. zvals are C structures
responsible of PHP variables, but not only. You really need to master that
special type management in order to play with PHP internals

Contents:

.. toctree::
   :maxdepth: 2

..

   zvals/structure.rst
   zvals/mem_management.rst
   zvals/main_macros.rst
   zvals/alloc_and_init.rst
   zvals/types.rst
   zvals/refcount_destruct.rst
   zvals/copy_separation.rst
   zvals/casts.rst
