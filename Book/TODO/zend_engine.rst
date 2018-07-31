Zend Engine
===========

The big part, Zend Engine is PHP's heart. It's composed of many different pieces
, each one having a responsibility. They all play together to make PHP alive.
Here you'll mainly dive into the virtual machine, and learn how PHP
understands its own code, how it executes it on the fly and how it makes a
response to your request.

Contents:

.. toctree::
    :maxdepth: 2

..
    zend_engine/lexer.rst
    zend_engine/parser.rst
    zend_engine/compiler.rst
    zend_engine/vm.rst
    zend_engine/vm_details.rst
    zend_engine/function_calls.rst
