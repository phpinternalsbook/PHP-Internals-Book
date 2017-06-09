Internal types
==============

In this chapter we will detail the special types used internally by PHP. Some of those types are directly bound to 
userland PHP, like the "zval" data structure. Other structures/types, like the "zend_string" one, is not really visible 
from userland point of view, but is a detail to know if you plan to program PHP from inside.

Contents:

.. toctree::
    :maxdepth: 2

    internal_types/zvals.rst
    internal_types/strings.rst
    internal_types/zend_resources.rst
    
..
    internal_types/hashtables.rst
    internal_types/objects/classes_and_objects.rst  
