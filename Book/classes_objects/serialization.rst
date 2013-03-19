Serialization
=============

In this section we'll have a look at PHP's serialization format and the different mechanisms PHP provides to serialize
object data. As usual we'll use the typed arrays implementation as an example.

PHP's serialization format
--------------------------

You probably already know how the output of ``serialize()`` roughly looks like: It has some kind of type specifier (like
``s`` or ``i``), followed by a colon, followed by the actual data, followed by a semicolon. As such the serialization
format for the "simple" types looks as follows:

.. code-block:: none

    NULL:         N;
    true:         b:1;
    false:        b:0;
    42:           i:42;

    42.3789:      d:42.378900000000002;
                    ^-- Precision controlled by serialize_precision ini setting (default 17)

    "foobar":     s:6:"foobar";
                    ^-- strlen("foobar")

    resource:     i:0;
                  ^-- Resources can't really be serialized, so they just get the value int(0)

For arrays a list of key-value pairs is contained in curly braces:

.. code-block:: none

    [10, 11, 12]:     a:3:{i:0;i:10;i:1;i:11;i:2;i:12;}
                       ^-- count([10, 11, 12])

                                                     v-- key   v-- value
    ["foo" => 4, "bar" => 2]:     a:2:{s:3:"foo";i:4;s:3:"bar";i:2;}
                                       ^-- key   ^-- value

For objects there are two serialization mechanisms: The first one simply serializes the object properties just like it
is done for arrays. This mechanism uses ``O`` as the type specifier.

Consider the following class:

.. code-block:: php

    <?php

    class Test {
        public $public = 1;
        protected $protected = 2;
        private $private = 3;
    }

This is serialized as follows:

.. code-block:: none

      v-- strlen("Test")           v-- property          v-- value
    O:4:"Test":3:{s:6:"public";i:1;s:12:"\0*\0protected";i:2;s:13:"\0Test\0private";i:3;}
                  ^-- property ^-- value                     ^-- property           ^-- value

The ``\0`` in the above serialization string are NUL bytes. As you can see private and protected members are serialized
with rather peculiar names: Private properties are prefixed with ``\0ClassName\0`` and protected properties with
``\0*\0``. These names are the result of name mangling, which is something we'll cover in a later section.

The second mechanism allows for custom serialization formats. It delegates the actual serialization to the ``serialize``
method of the ``Serializable`` interface and uses the ``C`` type specifier. For example consider this class:

.. code-block:: php

    <?php

    class Test2 implements Serializable {
        public function serialize() {
            return "foobar";
        }
        public function unserialize($str) {
            // ...
        }
    }

It will be serialized as follows:

.. code-block:: none

    C:5:"Test2":6:{foobar}
                ^-- strlen("foobar")

In this case PHP will just put the result of the ``Serializable::serialize()`` call inside the curly braces.

Another feature of PHP's serialization format is that it will properly preserve references:

.. code-block:: none

    $a = ["foo"];
    $a[1] =& $a[0];

    a:2:{i:0;s:3:"foo";i:1;R:2;}

The important part here is the ``R:2;`` element. It means "reference to the second value". What is the second value?
The whole array is the first value, the first index (``s:3:"foo"``) is the second value, so that's what is referenced.

As objects in PHP exhibit a reference-like behavior ``serialize`` also makes sure that the same object occurring twice
will really be the same object on unserialization:

.. code-block:: none

    $o = new stdClass;
    $o->foo = $o;

    O:8:"stdClass":1:{s:3:"foo";r:1;}

As you can see it works the same way as with references, just using the small ``r`` instead of ``R``.

Serializing internal objects
----------------------------

As internal objects don't store their data in ordinary properties PHP's default serialization mechanism will not work.
For example, if you try to serialize an ``ArrayBuffer`` all you'll get is this:

.. code-block:: none

    O:11:"ArrayBuffer":0:{}

Thus we'll have to write a custom handler for serialization. As mentioned above there are two ways in which objects can
be serialized (``O`` and ``C``). I'll demonstrate how to use both, starting with the ``C`` format that uses the
``Serializable`` interface. For this method we'll create our own serialization format based on the primitives that are
provided by ``serialize``. In order to do so we need to include two headers::

    #include "ext/standard/php_var.h"
    #include "ext/standard/php_smart_str.h"

The ``php_var.h`` header exports some serialization functions, the ``php_smart_str.h`` header contains PHPs
``smart_str`` API. This API provides a dynamically resized string structure, that allows us to easily create strings
without concerning ourselves with allocation.

Now let's see how the ``serialize`` method for an ``ArrayBuffer`` could look like::

    PHP_METHOD(ArrayBuffer, serialize)
    {
        buffer_object *intern;
        smart_str buf = {0};
        php_serialize_data_t var_hash;
        zval zv, *zv_ptr = &zv;

        if (zend_parse_parameters_none() == FAILURE) {
            return;
        }

        intern = zend_object_store_get_object(getThis() TSRMLS_CC);
        if (!intern->buffer) {
            return;
        }

        PHP_VAR_SERIALIZE_INIT(var_hash);

        INIT_PZVAL(zv_ptr);

        /* Serialize buffer as string */
        ZVAL_STRINGL(zv_ptr, (char *) intern->buffer, (int) intern->length, 0);
        php_var_serialize(&buf, &zv_ptr, &var_hash TSRMLS_CC);

        /* Serialize properties as array */
        Z_ARRVAL_P(zv_ptr) = zend_std_get_properties(getThis() TSRMLS_CC);
        Z_TYPE_P(zv_ptr) = IS_ARRAY;
        php_var_serialize(&buf, &zv_ptr, &var_hash TSRMLS_CC);

        PHP_VAR_SERIALIZE_DESTROY(var_hash);

        if (buf.c) {
            RETURN_STRINGL(buf.c, buf.len, 0);
        }
    }

Apart from the usual boilerplate this method contains a few interesting elements: Firstly, we declared a
``php_serialize_data_t var_hash`` variable, which is initialized with ``PHP_VAR_SERIALIZE_INIT`` and destroyed with
``PHP_VAR_SERIALIZE_DESTROY``. This variable is really of type ``HashTable*`` and is used to remember the serialized
values for the ``R``/``r`` reference preservation mechanism.

Furthermore we create a smart string using ``smart_str buf = {0}``. The ``= {0}`` initializes all members of the struct
with zero. This struct looks as follows::

    typedef struct {
        char *c;
        size_t len;
        size_t a;
    } smart_str;

``c`` is the buffer of the string, ``len`` the currently used length and ``a`` the size of the current allocation (as
this is smart string this doesn't necessarily match ``len``).

The serialization itself happens by using a dummy zval (``zv_ptr``). We first write a value into it and then call
``php_var_serialize``. The first serialized value is the actual buffer (as a string), the second value are the
properties (as an array).

A bit more complicated is the ``unserialize`` method::

    PHP_METHOD(ArrayBuffer, unserialize)
    {
        buffer_object *intern;
        char *str;
        int str_len;
        php_unserialize_data_t var_hash;
        const unsigned char *p, *max;
        zval zv, *zv_ptr = &zv;

        if (zend_parse_parameters(ZEND_NUM_ARGS() TSRMLS_CC, "s", &str, &str_len) == FAILURE) {
            return;
        }

        intern = zend_object_store_get_object(getThis() TSRMLS_CC);

        if (intern->buffer) {
            zend_throw_exception(
                NULL, "Cannot call unserialize() on an already constructed object", 0 TSRMLS_CC
            );
            return;
        }

        PHP_VAR_UNSERIALIZE_INIT(var_hash);

        p = (unsigned char *) str;
        max = (unsigned char *) str + str_len;

        INIT_ZVAL(zv);
        if (!php_var_unserialize(&zv_ptr, &p, max, &var_hash TSRMLS_CC)
            || Z_TYPE_P(zv_ptr) != IS_STRING || Z_STRLEN_P(zv_ptr) == 0) {
            zend_throw_exception(NULL, "Could not unserialize buffer", 0 TSRMLS_CC);
            goto exit;
        }

        intern->buffer = Z_STRVAL_P(zv_ptr);
        intern->length = Z_STRLEN_P(zv_ptr);

        INIT_ZVAL(zv);
        if (!php_var_unserialize(&zv_ptr, &p, max, &var_hash TSRMLS_CC)
            || Z_TYPE_P(zv_ptr) != IS_ARRAY) {
            zend_throw_exception(NULL, "Could not unserialize properties", 0 TSRMLS_CC);
            goto exit;
        }

        if (zend_hash_num_elements(Z_ARRVAL_P(zv_ptr)) != 0) {
            zend_hash_copy(
                zend_std_get_properties(getThis() TSRMLS_CC), Z_ARRVAL_P(zv_ptr),
                (copy_ctor_func_t) zval_add_ref, NULL, sizeof(zval *)
            );
        }

    exit:
        zval_dtor(zv_ptr);
        PHP_VAR_UNSERIALIZE_DESTROY(var_hash);
    }

The ``unserialize`` method again declares a ``var_hash`` variable, this time of type ``php_unserialize_data_t``,
initialized with ``PHP_VAR_UNSERIALIZE_INIT`` and destructed with ``PHP_VAR_UNSERIALIZE_DESTROY``. It has pretty much
the same function as its serialize equivalent: Storing variables for ``R``/``r``.

In order to use the ``php_var_unserialize`` function we need two pointers to the serialized string: The first one is
``p``, which is the current position in the string. The second one is ``max`` and points to the end of the string. The
``p`` position is passed to ``php_var_unserialize`` by-reference and will be modified to point to the start of the next
value that is to be unserialized.

The first unserialization reads the buffer, the second the properties. The largest part of the code is various error
handling. PHP has a long history of serialization related crashes (and security issues), so one should be careful to
ensure all the data is valid. You should also not forget that methods like ``unserialize`` even though they have a
special meaning can still called as normal methods. In order to prevent such calls the above call aborts if
``intern->buffer`` is already set.

[To be continued]