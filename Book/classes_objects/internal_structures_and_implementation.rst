Internal structures and implementation
======================================

In this (last) section on object orientation in PHP we'll have a look at some of the internal structures that were
previously only mentioned in passing. In particular we'll more thoroughly the default object structure and the object
store.

Object properties
-----------------

The probably by far most complicated part of PHP's object orientation system is the handling of object properties. In
the following we'll take a look at some of its parts in more detail.

Property storage
~~~~~~~~~~~~~~~~

In PHP object properties can be declared, but don't have to. How can one efficiently handle such a situation? To find
out let's recall the standard ``zend_object`` structure::

    typedef struct _zend_object {
        zend_class_entry *ce;
        HashTable *properties;
        zval **properties_table;
        HashTable *guards;
    } zend_object;

This structure contains two fields for storing properties: The ``properties`` hash table and the ``properties_table``
array of ``zval`` pointers. Two separate fields are used to best handle both declared and dynamic properties: For the
latter, i.e. properties that have not been declared in the class, there is no way around using the ``properties``
hash table (which uses a simple property name => value mapping).

For declared properties on the other hand storing them in a hashtable would be overly wasteful: PHP's hash tables
have a very high per-element overhead (of nearly one hundred bytes), but the only thing that really needs to be stored
is a ``zval`` pointer for the value. For this reason PHP employs a small trick: The properties are stored in a normal
C array and accessed using their offset. The offset for each property name is stored in a (global) hashtable in the
class entry. Thus the property lookup happens with one additional level of indirection, i.e. rather than directly
fetching the property value, first the property offset is fetched and that offset is then used to fetch the actual
value.

Property information (including the storage offset) is stored in ``class_entry->properties_info``. This hash table
is a map of property names to ``zend_property_info`` structs::

    typedef struct _zend_property_info {
        zend_uint flags;
        const char *name;
        int name_length;
        ulong h;                 /* hash of name */
        int offset;              /* storage offset */
        const char *doc_comment;
        int doc_comment_len;
        zend_class_entry *ce;    /* CE of declaring class */
    } zend_property_info;

One remaining question is what happens when both types of properties exist. In this case both structures will be used
simultaneously: All properties will be written into the ``properties`` hashtable, but ``properties_table`` will still
contain pointers to them. Note though that if both are used the properties table holds ``zval**`` values rather than
``zval*`` values.

Sometimes PHP needs the properties as a hashtable even if they are all declared, e.g. when the ``get_properties``
handler is used. In this case PHP also switches to using ``properties`` (or rather the hybrid approach described above).
This is done using the ``rebuild_object_properties`` function::

    ZEND_API HashTable *zend_std_get_properties(zval *object TSRMLS_DC)
    {
        zend_object *zobj;
        zobj = Z_OBJ_P(object);
        if (!zobj->properties) {
            rebuild_object_properties(zobj);
        }
        return zobj->properties;
    }

Property name mangling
~~~~~~~~~~~~~~~~~~~~~~

Consider the following code snippet:

.. code-block:: php

    <?php

    class A {
        private $prop = 'A';
    }

    class B extends A {
        private $prop = 'B';
    }

    class C extends B {
        protected $prop = 'C';
    }

    var_dump(new C);

    // Output:
    object(C)#1 (3) {
      ["prop":protected]=>
      string(1) "C"
      ["prop":"B":private]=>
      string(1) "B"
      ["prop":"A":private]=>
      string(1) "A"
    }

In the above example you can see the "same" property ``$prop`` being defined three times: Once as a private property of
``A``, once as a private property of ``B`` and once as a protected property of ``C``. Even though these three properties
have the same name they are still distinct properties and require separate storage.

In order to support this situation PHP "mangles" the property name by including the type of the property and the
defining class:

.. code-block:: none

    class Foo { private $prop;   } => "\0Foo\0prop"
    class Bar { private $prop;   } => "\0Bar\0prop"
    class Rab { protected $prop; } => "\0*\0prop"
    class Oof { public $prop;    } => "prop"

As you can see public properties have "normal" names, protected ones get a ``\0*\0`` prefix (where ``\0`` are NUL bytes)
and private ones start with ``\0ClassName\0``.

Most of the time PHP does a good job hiding the mangled names from userland. You only get to see them in some rare
cases, e.g. if you cast an object to array or look at serialization output. Internally you usually don't need to care
about mangled names either, e.g. when using the ``zend_declare_property`` APIs the mangling is automatically done for
you.

The only places where you have to look out for mangled names is if you access the ``property_info->name`` field or if
you try to directly access the ``zobj->properties`` hash. In this cases you can use the
``zend_(un)mangle_property_name`` APIs::

    // Unmangling
    const char *class_name, *property_name;
    int property_name_len;

    if (zend_unmangle_property_name_ex(
            mangled_property_name, mangled_property_name_len,
            &class_name, &property_name, &property_name_len
        ) == SUCCESS) {
        // ...
    }

    // Mangling
    char *mangled_property_name;
    int mangled_property_name_len;

    zend_mangle_property_name(
        &mangled_property_name, &mangled_property_name_len,
        class_name, class_name_len, property_name, property_name_len,
        should_do_persistent_alloc ? 1 : 0
    );

Property recursion guards
~~~~~~~~~~~~~~~~~~~~~~~~~

The last member in ``zend_object`` is the ``HashTable *guards`` field. To find out what it is used for, consider what
happens in the following code using magic ``__set`` properties:

.. code-block:: php

    <?php

    class Foo {
        public function __set($name, $value) {
            $this->$name = $value;
        }
    }

    $foo = new Foo;
    $foo->bar = 'baz';
    var_dump($foo->bar);

The ``$foo->bar = 'baz'`` assignment in the script will call ``$foo->__set('bar', 'baz')`` as the ``$bar`` property is
not defined. The ``$this->$name = $value`` line in the method body in this case would become ``$foo->bar = 'baz'``.
Once again ``$bar`` is an undefined property. So, does that mean that the ``__set`` method will be (recursively) called
again?

That's not what happens. Rather PHP sees that it is already within ``__set`` and does *not* do a recursive call. Instead
it actually creates the new ``$bar`` property. In order to implement this behavior PHP uses recursion guards which
remember whether PHP is already in ``__set`` etc for a certain property. These guards are stored in the ``guards`` hash
table, which maps property names to ``zend_guard`` structures::

    typedef struct _zend_guard {
        zend_bool in_get;
        zend_bool in_set;
        zend_bool in_unset;
        zend_bool in_isset;
        zend_bool dummy; /* sizeof(zend_guard) must not be equal to sizeof(void*) */
    } zend_guard;

Object store
------------

We already made a lot of use of the object store, so let's have a closer look at it now::

    typedef struct _zend_objects_store {
        zend_object_store_bucket *object_buckets;
        zend_uint top;
        zend_uint size;
        int free_list_head;
    } zend_objects_store;

The object store is basically a dynamically resized array of ``object_buckets``. ``size`` specifies the size of the
allocation, whereas ``top`` is the next object handle to be used. Handles are counted starting from 1, to ensure that
all handles are "truthy". Thus if ``top == 1`` the next object will get ``handle = 1``, but will be put at position
``object_buckets[0]``.

The ``free_list_head`` is the head of a linked list of unused buckets. Whenever an object is destroyed it leaves behind
an unused bucket, which is then put in this list. If a new object is created and such a bucket exists (i.e.
``free_list_head`` is not ``-1``), then this bucket is used instead of the ``top`` one.

To see how this linked list is maintained have a look at the ``zend_object_store_bucket`` structure::

    typedef struct _zend_object_store_bucket {
        zend_bool destructor_called;
        zend_bool valid;
        zend_uchar apply_count;
        union _store_bucket {
            struct _store_object {
                void *object;
                zend_objects_store_dtor_t dtor;
                zend_objects_free_object_storage_t free_storage;
                zend_objects_store_clone_t clone;
                const zend_object_handlers *handlers;
                zend_uint refcount;
                gc_root_buffer *buffered;
            } obj;
            struct {
                int next;
            } free_list;
        } bucket;
    } zend_object_store_bucket;

If the bucket is in use (i.e. stores an object), then the ``valid`` member will be 1. In this case the
``struct _store_object`` part of the union will be used. If the bucket is not used, then ``valid`` will be 0 and PHP
will make use of ``free_list.next``.

This reclaiming of unused object handles can be shown with a small script:

.. code-block:: php

    <?php
    var_dump($a = new stdClass); // object(stdClass)#1 (0) {}
    var_dump($b = new stdClass); // object(stdClass)#2 (0) {}
    var_dump($c = new stdClass); // object(stdClass)#3 (0) {}

    unset($b); // free handle 2
    unset($a); // free handle 1

    var_dump($e = new stdClass); // object(stdClass)#1 (0) {}
    var_dump($f = new stdClass); // object(stdClass)#2 (0) {}

As you can see the handles of ``$b`` and ``$a`` are reused in reverse order of destruction.

Apart from ``valid`` the bucket structure also contains a ``destructor_called`` flag. This flag is needed for PHP's
two-phase object destruction process: As already outlined previously PHP has distinct dtor (can run userland code, isn't
always run) and free (must not run userland code, is always executed) phases. After the dtor handler has been called,
the ``destructor_called`` flag is set to 1, so that the dtor is not run again when the object is freed.

The ``apply_count`` member serves the same role as the ``nApplyCount`` member of ``HashTable``: It protects against
infinite recursion. It is used via the macros ``Z_OBJ_UNPROTECT_RECURSION(zval_ptr)`` (leave recursion) and
``Z_OBJ_PROTECT_RECURSION(zval_ptr)`` (enter recursion). The latter will throw an error if the nesting level for an
object is 3 or larger. Currently this protection mechanism is only used in the object comparison handler.

The ``handlers`` member in the ``_store_object`` struct is also required for destruction. The reason for this is that
the ``dtor`` handler only gets passed the stored object and its handle::

    typedef void (*zend_objects_store_dtor_t)(void *object, zend_object_handle handle TSRMLS_DC);

But in order to call ``__destruct`` PHP needs a zval. Thus it creates a temporary zval using the passed object handle
and the object handlers stored in ``bucket.obj.handlers``. The issue is that this member can only be set if the object
is destructed through ``zval_ptr_dtor`` or some other method where the zval (and as such the object handlers) is known.

If on the other hand the object is destroyed during shutdown (using ``zend_objects_store_call_destructors``) the zval
is *not* known. In this case ``bucket.obj.handlers`` will be ``NULL`` and PHP falls back to the default object handlers.
Thus it can sometimes happen that overloaded object behavior is not available in ``__destruct``. An example:

.. code-block:: php

    class DLL extends SplDoublyLinkedList {
        public function __destruct() {
            var_dump($this);
        }
    }

    $dll = new DLL;
    $dll->push(1);
    $dll->push(2);
    $dll->push(3);

    var_dump($dll);

    set_error_handler(function() use ($dll) {});

This code snippet adds a ``__destruct`` method to ``SplDoublyLinkedList`` and then forces the destructor to be called
during shutdown by binding it to the error handler (the error handler is one of the last things that is freed during
shutdown.) This will produce the following output:

.. code-block:: none

    object(DLL)#1 (2) {
      ["flags":"SplDoublyLinkedList":private]=>
      int(0)
      ["dllist":"SplDoublyLinkedList":private]=>
      array(3) {
        [0]=>
        int(1)
        [1]=>
        int(2)
        [2]=>
        int(3)
      }
    }
    object(DLL)#1 (0) {
    }

For the ``var_dump`` outside the destructor ``get_debug_info`` is invoked and you get meaningful debugging output.
Inside the destructor PHP uses the default object handlers and as such you don't get anything apart from the class
name. The same also applies to other handlers, e.g. things like cloning, comparison, etc will not work properly.

This concludes the chapter on object orientation. You should now have a good understanding of how the object orientation
system in PHP works and how extensions can make use of it.