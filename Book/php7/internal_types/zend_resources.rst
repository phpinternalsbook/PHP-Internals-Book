The Resource type: zend_resource
================================

Even though PHP could really get rid of the "resource" type, because
:doc:`custom object storage <./classes_objects/custom_object_storage>` allows to build a PHP representation of any
abstract kind of data, that resource type still exists in the current version of PHP, and you may need to deal with it.

If you need to create resources, we really would like to push you not to, but instead use objects and their
:doc:`custom storage <./classes_objects/custom_object_storage>` management. Objects is the PHP type that can embed
anything of any type. However, for historical reasons, PHP still knows about that special type "Resource", and still
makes use of it in its heart or in some extensions. Let's see that type together. Beware however, it is really cryptic
and suffers from a long past history, so don't be surprised about its design especially when reading the source code
about it

What is the "Resource" type?
----------------------------

Easy enough you know about it. We are talking about this here:

.. code-block:: php

    $fp = fopen('/proc/cpuinfo', 'r');
    var_dump($fp); /* resource(2) of type (stream) */

Internally, a resource is bound to the ``zend_resource`` structure type::

    struct _zend_resource {
	    zend_refcounted_h gc;
	    int               handle;
	    int               type;
	    void             *ptr;
    };

We find the traditional ``zend_refcounted_h`` header, meaning that resources are reference countable. If you feel lost
with reference counting and memory tracking, you may refer to the :doc:`./zvals/memory_management` chapter.

The ``handle`` is an integer that is used internally by the engine to locate the resource into an internal resource
table. It is used as the key for such a table.

The ``type`` is used to regroup resources of the same type together. This is about the way resources get destroyed and
how they are fetched back from their handle.

Finally, the ``ptr`` field in ``zend_resource`` is your abstract data. Remember resources are about storing an abstract
data that cannot fit in any data type PHP can represent natively (but objects could, like we said earlier).

Resource types and resource destruction
---------------------------------------

Resources must register a destructor. When users use resources in PHP userland, they usually don't bother cleaning
those when they don't make use of them anymore. For example, it is not uncommon to see an ``fopen()`` call, and not see
the matching ``fclose()`` call. Using the C language, this would be at best a bad idea, at most a disaster. But using a
high level language like PHP, you ease things.

You, as an internal developer, must be prepared to the fact that the user would create a lot of resources you'll allow
him to use, without properly cleaning them and releasing memory/OS resource. You hence must register a destructor that
will be called anytime the engine is about to destroy a resource of that type.

Destructors are grouped by types, so are resources themselves. You won't apply the destructor for a resource of type
'database' than for a resource of type 'file'.

There also exists two kinds of resources, here again differentiated about their lifetime.

* Classical resources, the most used ones, do not persist across several requests, their destructor is called at
  request shutdown.
* Persistent resources will persist across several requests and will only get destroyed when the PHP process dies.

.. note:: You may be interested by :doc:`the PHP lifecycle <../extensions_design/php_lifecycle>` chapter that shows you
          the different steps occurring in PHP's process life. Also, the
          :doc:`Zend Memory Manager chapter <../memory_management/zend_memory_manager>` may help in understanding
          concepts of persistent and request-bound memory allocations.

Playing with resources
----------------------

The resources related API can be found in
`zend/zend_list.c <https://github.com/php/php-src/blob/3704947696fe0ee93e025fa85621d297ac7a1e4d/Zend/zend_list.c>`_.
You may find some inconsistencies into it, like talking about "lists" for "resources".

Creating resources
******************

To create a resource, one must first register a destructor for it and associate it to a resource type name using
``zend_register_list_destructors_ex()``. That call will return an integer that represents the type of resource you
register. You must remember that integer because you will need it later-on to fetch back your resource from the user.

After that, you can register a new resource using ``zend_register_resource()``. That one will return you a
``zend_resource``. Let's see together a simple use-case example::

    #include <stdio.h>

    int res_num;
    FILE *fp;
    zend_resource *my_res;
    zval my_val;

    static void my_res_dtor(zend_resource *rsrc)
    {
        fclose((FILE *)rsrc->ptr);
    }

    /* module_number should be your PHP extension number here */
    res_num = zend_register_list_destructors_ex(my_res_dtor, NULL, "my_res", module_number);
    fp      = fopen('/proc/cpuinfo', "r");
    my_res  = zend_register_resource((void *)fp, res_num);

    ZVAL_RES(&my_val, my_res);

What we do in the code above, is that we open a file using libc's ``fopen()``, and store the returned pointer into a
resource. Before that, we registered a destructor which when called will use libc's ``fclose()`` on the pointer. Then,
we register the resource against the engine, and we pass the resource into a ``zval`` container that could get returned
to userland.

.. note:: Zvals chapter can be found :doc:`here <./zvals>`.

What must be remembered is resource type. Here, we register a resource of type *"my_res"*. This is the type name. The
engine does not really care about type name, but type identifier, the integer returned by
``zend_register_list_destructors_ex()``. You should remember it somewhere, like we do in the ``res_num`` variable.

Fetching back resources
***********************

Now that we registered a resource and put it in a ``zval`` for an example, we should learn how to fetch back that
resource from the userland. Remember, the resource is stored into the ``zval``. Into the resource is stored the resource
type number (on the ``type`` field). Thus, to be given back our resource from the user, we must extract the
``zend_resource`` from the ``zval``, and call ``zend_fetch_resource()`` to get back our ``FILE *`` pointer::

    /* ... later on ... */

    zval *user_zval = /* fetch zval from userland, assume type IS_RESOURCE */

    ZEND_ASSERT(Z_TYPE_P(user_zval) == IS_RESOURCE); /* just a check to be sure */

    fp = (FILE *)zend_fetch_resource(Z_RESVAL_P(user_zval), "my_res", res_num);

Like we said : get back a zval from the user (of type ``IS_RESOURCE``), and fetch the resource pointer back from it by
calling ``zend_fetch_resource()``.

That function will check if the type of the resource is of the type you pass as third parameter (``res_num`` here).
If yes, it extracts back the ``void *`` resource pointer you need and we are done. If not, then it throws a warning like
*"supplied resource is not a valid {type name} resource"*.
This could happen if for example you expect a resource of type "my_res", and you are given a zval with a resource of
type "gzip", like one returned by ``gzopen()`` PHP function.

Resource types are just a way for the engine to mix different kind of resources (of type "file", "gzip" or even "mysql
connection") into the same resource table. Resource types have names, so that those can be used in error messages or in
debug statement (like a ``var_dump($my_resource)``), and they also are represented as an integer used internally to
fetch back the resource pointer from it, and to register a destructor with the resource type.

.. note:: Like you can see, if we would have used objects, those represent types by themselves, and there wouldn't have
          to happen that step of fetching back a resource from its identifier verifying its type. Objects are
          self-describing types. But resources are still a valid data type for the current PHP version.

Reference counting resources
----------------------------

Like many other types, ``zend_resource`` is reference counted. We can see its ``zend_refcounted_h`` header. Here is the
API to play with reference counting, if you need it (you shouldn't really need it on an average):

* ``zend_list_delete(zend_resource *res)`` decrements refcount and destroys resource if drops to zero
* ``zend_list_free(zend_resource *res)`` checks if refcount is zero, and destroys the resource if true.
* ``zend_list_close(zend_resource *res)`` calls the resource destructor whatever the conditions

Persistent resources
--------------------

Persistent resources don't get destroyed at the end of the request. The classical use-case for that are persistent
database connections. Those are connections that are recycled from request to request (with all the bullshit that will
bring).

Traditionally, you should not be using persistent resources, as one request will be different from the other. Reusing
the same resource should really be thoughtful before going this way.

To register a persistent resource, use a persistent destructor instead of a classical one. This is done in the call
to ``zend_register_list_destructors_ex()``, which API is like::

    zend_register_list_destructors_ex(rsrc_dtor_func_t destructor, rsrc_dtor_func_t persistent_destructor,
                                      const char *type_name, int module_number);
