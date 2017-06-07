The Resource type: zend_resource
================================

Even though PHP could really get rid of the "resource" type, because custom object storage allows to build a PHP
representation of any abstract kind of data, that resource type still exists in PHP, and you may need to cope with it.

If you need to create resources, we really would like to push you not to, but instead use objects and their custom
storage management. Objects is the PHP type that can embed anything of any type.
However, for historical reasons, PHP still knows about that special type "Resource", and still makes use of it in its 
heart or in some extensions. Let's see that type together. Beware however, it is really cryptic and suffers from a long 
past history, so don't be suprised about its design.

What is the "Resource" type ?
-----------------------------

Easy enough you know about it. We are talking about this here:

.. code-block:: php
    
    $fp = fopen('/proc/cpuinfo', 'r');
    var_dump($fp); /* resource(2) of type (stream) */

Internally, a resource is bound to the zend_resource structure type::

    struct _zend_resource {
	    zend_refcounted_h gc;
	    int               handle;
	    int               type;
	    void             *ptr;
    };

We find the traditionnal ``zend_refcount_h`` header, meaning that resources are reference countable. If you feel lost
with reference counting and memory tracking, you may refer to the :doc:`./zvals/memory_management` chapter.

The ``handle`` is an integer that is used internally by the engine to locate the resource into an internal resource 
table. It is used as the key for such a table.

The ``type`` is used to regroup resources of the same type together. This is about the way resources get destroyed: 
if two resources share the same destructor (pretty uncommon), they should use the same type. ``type`` is of type 
integer.

Finally, the ``ptr`` field in ``zend_resource`` is your abstract data. Remember resources are about storing an abstract 
data that cannot fit in any data type PHP can represent natively.

Resource types and resource destruction
---------------------------------------

Resources must register a destructor. When users use resources in PHP userland, they usually don't bother cleaning 
those when they don't make use of them anymore. For example, it is not uncommon to see an ``fopen()`` call, and not see 
the ``fclose()`` call. Using the C language, this would be at least a bad idea, at most a disaster. But using a high 
level language like PHP, you ease things.

You, as an internal developer, must be prepared to the fact that the user would create a lot of resources you'll allow 
him to use, without properly cleaning them and releasing memory/OS resource. You hence must register a destructor that 
will be called anytime the engine is about to destroy a resource.

There exists two kinds of resources, here again differenciated about their lifetime.

* Classical resources, the most used once, do not persist accross several requests, their destructor is called at 
  request shutdown
* Persistent resources will persist accross several requests and will only get destroyed when the PHP process dies.

Playing with resources
----------------------

The resources related API can be found in 
`zend/zend_list.c <https://github.com/php/php-src/blob/3704947696fe0ee93e025fa85621d297ac7a1e4d/Zend/zend_list.c>`_.
You may find some inconsistencies into it, like talking about "lists" for "resources".

To create a resource, one must first register a destructor for it using ``zend_register_list_destructors_ex()``. That 
call will return an integer that represents the type of resource you register. You must remember that integer because 
you will need it later on to fetch back your resource from the user.

After that, you can register a new resource using ``zend_register_resource()``. That one will return you a 
``zend_resource``. Let's see together a simple use-case example::

    #include <stdio.h>
    
    static int res_num;
    FILE *fp;
    zend_resource *my_res;
    zval my_val;
    
    static void my_res_dtor(zend_resource *rsrc)
    {
        fclose((FILE *)rsrc->ptr);
    }

    res_num = zend_register_list_destructors_ex(my_res_dtor, NULL, "my_res", module_number);
    fp      = fopen('/proc/cpuinfo', "r");
    my_res  = zend_register_resource((void *)fp, res_num);
    
    ZVAL_RES(&my_val, my_res);

What we do in the code above, is that we open a file using libc's ``fopen()``, and store the returned pointer into a 
resource. Before that, we registered a destructor which will use libc's ``fclose()`` on the pointer. Then, we register 
the resource against the engine, and we pass the resource into a ``zval`` container that could get returned to userland.

.. note:: Zvals chapter can be found :doc:`here <./zvals>`.

Later on, it will be useful to fetch back that resource from userland. F.e, the user would pass us a variable, a 
``zval``, of type ``IS_RESOURCE``. We would then need to check if the resource into it is of the kind we expect, as the 
user may pass us a resource of another type (like f.e, the return of the ``gzopen()`` PHP function).
