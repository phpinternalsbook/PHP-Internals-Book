Internal structures and implementation
======================================

In this (last) section on object orientation in PHP we'll have a look at some of the internal structures that were
previously only mentioned in passing. In particular we'll more thoroughly discuss class entries, the object store and
the default object structure.

Object properties
-----------------

The probably by far most complicated part of PHP's object orientation system is the handling of object properties. In
the following we'll take a look at some of its parts in more detail.

Property storage
~~~~~~~~~~~~~~~~

In PHP object properties can be declared, but don't have to. How can one efficiently handle such a situation? To find
out lets recall the standard ``zend_object`` structure::

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
handler is used. In this case PHP also switches to using ``properties`` or rather the hybrid approach described above.
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

The last member in ``zend_object`` which we didn't yet look at is the ``HashTable *guards`` fields. To find out what it
is used for, consider what happens in the following code using magic ``__set`` properties:

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

.. todo:: stopped here

..
    struct _zend_class_entry {
        char type;
        const char *name;
        zend_uint name_length;
        struct _zend_class_entry *parent;
        int refcount;
        zend_uint ce_flags;

        HashTable function_table;
        HashTable properties_info;
        zval **default_properties_table;
        zval **default_static_members_table;
        zval **static_members_table;
        HashTable constants_table;
        int default_properties_count;
        int default_static_members_count;

        union _zend_function *constructor;
        union _zend_function *destructor;
        union _zend_function *clone;
        union _zend_function *__get;
        union _zend_function *__set;
        union _zend_function *__unset;
        union _zend_function *__isset;
        union _zend_function *__call;
        union _zend_function *__callstatic;
        union _zend_function *__tostring;
        union _zend_function *serialize_func;
        union _zend_function *unserialize_func;

        zend_class_iterator_funcs iterator_funcs;

        /* handlers */
        zend_object_value (*create_object)(zend_class_entry *class_type TSRMLS_DC);
        zend_object_iterator *(*get_iterator)(zend_class_entry *ce, zval *object, int by_ref TSRMLS_DC);
        int (*interface_gets_implemented)(zend_class_entry *iface, zend_class_entry *class_type TSRMLS_DC); /* a class implements this interface */
        union _zend_function *(*get_static_method)(zend_class_entry *ce, char* method, int method_len TSRMLS_DC);

        /* serializer callbacks */
        int (*serialize)(zval *object, unsigned char **buffer, zend_uint *buf_len, zend_serialize_data *data TSRMLS_DC);
        int (*unserialize)(zval **object, zend_class_entry *ce, const unsigned char *buf, zend_uint buf_len, zend_unserialize_data *data TSRMLS_DC);

        zend_class_entry **interfaces;
        zend_uint num_interfaces;

        zend_class_entry **traits;
        zend_uint num_traits;
        zend_trait_alias **trait_aliases;
        zend_trait_precedence **trait_precedences;

        union {
            struct {
                const char *filename;
                zend_uint line_start;
                zend_uint line_end;
                const char *doc_comment;
                zend_uint doc_comment_len;
            } user;
            struct {
                const struct _zend_function_entry *builtin_functions;
                struct _zend_module_entry *module;
            } internal;
        } info;
    };