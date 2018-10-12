Simple classes
==============

Basic concepts
--------------

Zvals store objects using the ``IS_OBJECT`` type tag and the ``zend_object_value`` structure in the union, which is
defined as follows::

    typedef struct _zend_object_value {
        zend_object_handle handle;
        const zend_object_handlers *handlers;
    } zend_object_value;

The first part of the structure, the ``zend_object_handle``, is just a typedef for an unsigned integer. It is an ID
uniquely identifying the object and is used to fetch the actual object data from the object store.

The second part is a pointer to a structure of object handlers. These handlers define the actual behavior of the object.
They cover everything from property fetches and method calls to custom comparison handling or even special garbage
collection semantics.

When called, the individual handlers get passed the object zval as the first argument, followed by various
handler-specific information. They can then use the object handle to fetch the object data from the object store and do
operations on it.

The complementary structure to the object value is the class entry (``zend_class_entry``). Class entries contain a large
amount of information, including the class methods and static properties as well as various handlers, in particular a
handler for creating objects from the class.

Class registration
------------------

Just like functions classes are registered in the extension's ``MINIT`` handler. Here is a snippet for declaring an
empty ``Test`` class::

    zend_class_entry *test_ce;

    const zend_function_entry test_functions[] = {
        PHP_FE_END
    };

    PHP_MINIT_FUNCTION(test)
    {
        zend_class_entry tmp_ce;
        INIT_CLASS_ENTRY(tmp_ce, "Test", test_functions);

        test_ce = zend_register_internal_class(&tmp_ce TSRMLS_CC);

        return SUCCESS;
    }

The first line declares a global variable ``test_ce``, which will hold the class entry of the ``Test`` class. It is a
"true" global variable (without thread safety protection) and should additionally be exported via the header file, so
that other extensions can make use of the class. The following three lines declare an array for the class methods, just
like you would do for normal functions.

Then the main code follows: First a temporary class entry value ``tmp_ce`` is defined and then initialized using
``INIT_CLASS_ENTRY``. After that the class is registered in the Zend Engine using ``zend_register_internal_class``. This
function also returns the final class entry, so it can be stored in the global variable declared above.

To test that the class was registered properly you can run ``php --rc Test``, which should give an output along the
following lines:

.. code-block:: none

    Class [ <internal:test> class Test ] {
      - Constants [0] {
      }
      - Static properties [0] {
      }
      - Static methods [0] {
      }
      - Properties [0] {
      }
      - Methods [0] {
      }
    }

As expected what you get is a totally empty class.

Method definition and declaration
---------------------------------

To bring it to life let's add a method::

    PHP_METHOD(Test, helloWorld) /* {{{ */
    {
        if (zend_parse_parameters_none() == FAILURE) {
            return;
        }

        RETURN_STRING("Hello World\n", 1);
    }
    /* }}} */

    ZEND_BEGIN_ARG_INFO_EX(arginfo_void, 0, 0, 0)
    ZEND_END_ARG_INFO()

    const zend_function_entry test_functions[] = {
        PHP_ME(Test, helloWorld, arginfo_void, ZEND_ACC_PUBLIC)
        PHP_FE_END
    };

As you can see a method declaration looks very similar to a function declaration. Instead of ``PHP_FUNCTION`` we use
``PHP_METHOD`` and pass it both the class and method name. In the ``zend_function_entry`` array ``PHP_ME`` is used
instead of ``PHP_FE``. It again takes the class name, the method name, the arginfo struct and additionally a set of
flags.

The flags parameter allows you to specify the usual PHP method modifiers using a combination of ``ZEND_ACC_PUBLIC``,
``ZEND_ACC_PROTECTED``, ``ZEND_ACC_PRIVATE``, ``ZEND_ACC_STATIC``, ``ZEND_ACC_FINAL`` and ``ZEND_ACC_ABSTRACT``. For
example a protected final static method would be declared as follows::

    PHP_ME(
        Test, protectedFinalStaticMethod, arginfo_xyz,
        ZEND_ACC_PROTECTED | ZEND_ACC_FINAL | ZEND_ACC_STATIC
    )

As abstract methods do not have an associated implementation the ``ZEND_ACC_ABSTRACT`` flag is not used directly.
Instead a special macro is provided::

    PHP_ABSTRACT_ME(Test, abstractMethod, arginfo_abc)

Analogous to what happens for ``PHP_FUNCTION`` the ``PHP_METHOD`` macro expands into a function declaration with a
special name, which you may encounter when looking at backtraces within method calls::

    PHP_METHOD(ClassName, methodName) { }
    /* expands to */
    void zim_ClassName_methodName(INTERNAL_FUNCTION_PARAMETERS) { }

But now, let's get back to writing methods. Here is another one::

    PHP_METHOD(Test, getOwnObjectHandle)
    {
        zval *obj;

        if (zend_parse_parameters_none() == FAILURE) {
            return;
        }

        obj = getThis();

        RETURN_LONG(Z_OBJ_HANDLE_P(obj));
    }

    //...
        PHP_ME(Test, getOwnObjectHandle, arginfo_void, ZEND_ACC_PUBLIC)
    //...

This method does nothing more than return the object's own object handle. To do this it first grabs the ``$this`` zval
using the ``getThis()`` macro and then returns the object handle provided by ``Z_OBJ_HANDLE_P``. Try it out:

.. code-block:: php

    $t1 = new Test;
    $other = new stdClass;
    $t2 = new Test;
    echo $t1, "\n", $t2, "\n";

This will (probably) output the numbers 1 and 3, so you can see that the object handle is basically just a number
which is incremented with every new object. (This isn't exactly true because object handles can be reused again once the
associated objects are destroyed.)

Properties and constants
------------------------

To do something more useful, let's create two methods for reading from and writing to a property::

    PHP_METHOD(Test, getFoo)
    {
        zval *obj, *foo_value;

        if (zend_parse_parameters_none() == FAILURE) {
            return;
        }

        obj = getThis();

        foo_value = zend_read_property(test_ce, obj, "foo", sizeof("foo") - 1, 1 TSRMLS_CC);

        RETURN_ZVAL(foo_value, 1, 0);
    }

    PHP_METHOD(Test, setFoo)
    {
        zval *obj, *new_foo_value;

        if (zend_parse_parameters(ZEND_NUM_ARGS() TSRMLS_CC, "z", &new_foo_value) == FAILURE) {
            return;
        }

        obj = getThis();

        zend_update_property(test_ce, obj, "foo", sizeof("foo") - 1, new_foo_value TSRMLS_CC);
    }

    // ...

    ZEND_BEGIN_ARG_INFO_EX(arginfo_void, 0, 0, 0)
    ZEND_END_ARG_INFO()

    ZEND_BEGIN_ARG_INFO_EX(arginfo_set, 0, 0, 1)
        ZEND_ARG_INFO(0, value)
    ZEND_END_ARG_INFO()

    // ...
        PHP_ME(Test, getFoo, arginfo_void, ZEND_ACC_PUBLIC)
        PHP_ME(Test, setFoo, arginfo_set, ZEND_ACC_PUBLIC)
    // ...

The two new functions in the above code are ``zend_read_property()`` and ``zend_update_property()``. Both functions take
the scope as first parameter, the object as second and the property name and length after that. The "scope" here is
a class entry and is necessary for visibility handling. If ``foo`` is a public property the used scope doesn't matter
(it could just as well be ``NULL``), but if it were a private property we could only access it with the class entry of
the class it belongs to.

``zend_update_property()`` additionally takes the new value for the property as last parameter. ``zend_read_property()``
on the other hand takes an additional boolean ``silent`` parameter. It specifies whether PHP should suppress the
"Undefined property xyz" notice. In our case we don't know whether the property exists beforehand, so we pass ``1``
(meaning: no notice).

We can try the new functionality out:

.. code-block:: php

    $t = new Test;
    var_dump($t->getFoo()); // NULL (and no notice, because we passed silent=1)

    $t->setFoo("abc");
    var_dump($t->foo);      // "abc"
    var_dump($t->getFoo()); // "abc"

    $t->foo = "def";
    var_dump($t->foo);      // "def"
    var_dump($t->getFoo()); // "def"

``zend_update_property()`` also comes in several variants that allow setting specific values more easily (i.e. without
manually creating a zval):

 * ``zend_update_property_null(... TSRMLS_DC)``
 * ``zend_update_property_bool(..., long value TSRMLS_DC)``
 * ``zend_update_property_long(..., long value TSRMLS_DC)``
 * ``zend_update_property_double(..., double value TSRMLS_DC)``
 * ``zend_update_property_string(..., const char *value TSRMLS_DC)``
 * ``zend_update_property_stringl(..., const char *value, int value_len TSRMLS_DC)``

In the above example we had to use the ``silent=1`` parameter, because we didn't have the guarantee that the ``foo``
property would exist when we read it. A better way to solve this is to properly declare the property when the class is
registered, just like you would write ``public $foo = DEFAULT_VALUE;`` in PHP.

This is done using the ``zend_declare_property()`` function family, which features the same variants as
``zend_update_property()``. For example to declare a public ``foo`` property with a ``null`` default value we have to add
the following line after the class registration in ``MINIT``::

    zend_declare_property_null(test_ce, "foo", sizeof("foo") - 1, ZEND_ACC_PUBLIC TSRMLS_CC);

To create a protected property defaulting to the string ``"bar"`` you instead write::

    zend_declare_property_string(
        test_ce, "foo", sizeof("foo") - 1, "bar", ZEND_ACC_PROTECTED TSRMLS_CC
    );

If you want to use properties (and you will soon find that this is only rarely necessary for internal classes) it is
always good practice to properly declare properties. This way you have an explicit visibility level, a default value
and you also benefit from memory optimizations for declared properties.

Static properties are also declared using the same family of functions by additionally specifying the
``ZEND_ACC_STATIC`` flag. A public static ``$pi`` property::

    zend_declare_property_double(
        test_ce, "pi", sizeof("pi") - 1, 3.141, ZEND_ACC_PUBLIC | ZEND_ACC_STATIC TSRMLS_CC
    );
    /* All digits of pi I remember :( */

To read and update static properties there are the ``zend_read_static_property()`` function and the
``zend_update_static_property()`` function family. They have the same interface as the functions for normal properties,
only difference being that no object is passed (only the scope).

To declare constants the ``zend_declare_class_constant_*()`` family of functions is used. They have the same variations and
signatures as ``zend_declare_property_*()``, only without the flags argument. To declare a constant ''Test::PI''::

    zend_declare_class_constant_double(test_ce, "PI", sizeof("PI") - 1, 3.141 TSRMLS_CC);

Inheritance and interfaces
--------------------------

Just like their userland equivalents internal classes can also inherit from other classes and/or implement interfaces.

A very simple (and quite common) example of inheritance in the PHP tree is creating some custom subtype of
``Exception``::

    zend_class_entry *custom_exception_ce;

    PHP_MINIT_FUNCTION(Test)
    {
        zend_class_entry tmp_ce;
        INIT_CLASS_ENTRY(tmp_ce, "CustomException", NULL);
        custom_exception_ce = zend_register_internal_class_ex(
            &tmp_ce, zend_exception_get_default(TSRMLS_C), NULL TSRMLS_CC
        );

        return SUCCESS;
    }

The new thing here is the use of ``zend_register_internal_class_ex()`` (with the ``_ex``), which does the same thing as
``zend_register_internal_class()``, but additionally allows you to specify the parent class entry. Here the parent CE is
fetched using ``zend_exception_get_default(TSRMLS_C)``. Another detail worth pointing out is that we did not define a
function structure and instead just passed ``NULL`` as the last argument to ``INIT_CLASS_ENTRY``. This means that we
don't want any additional methods, apart from those that are inherited from ``Exception``.

If you want to extend a more specific SPL extension class like ``RuntimeException`` you can also do so::

    #ifdef HAVE_SPL
    #include "ext/spl/spl_exceptions.h"
    #endif

    zend_class_entry *custom_exception_ce;

    PHP_MINIT_FUNCTION(Test)
    {
        zend_class_entry tmp_ce;
        INIT_CLASS_ENTRY(tmp_ce, "CustomException", NULL);

    #ifdef HAVE_SPL
        custom_exception_ce = zend_register_internal_class_ex(
            &tmp_ce, spl_ce_RuntimeException, NULL TSRMLS_CC
        );
    #else
        custom_exception_ce = zend_register_internal_class_ex(
            &tmp_ce, zend_exception_get_default(TSRMLS_C), NULL TSRMLS_CC
        );
    #endif

        return SUCCESS;
    }

The above code conditionally either inherits from ``RuntimeException`` or - if SPL is not compiled in - from just
``Exception``. The class entry for ``RuntimeException`` is externed in the header ``ext/spl/spl_exceptions.h``, so it
has to be included as well.

The last parameter of ``zend_register_internal_class_ex()`` which was set to ``NULL`` in the above cases, is an
alternative way to specify the parent class: If you don't have the class entry available you can specify the class
name::

    custom_exception_ce = zend_register_internal_class_ex(
        &tmp_ce, spl_ce_RuntimeException, NULL TSRMLS_CC
    );
    /* can also be written as */
    custom_exception_ce = zend_register_internal_class_ex(
        &tmp_ce, NULL, "RuntimeException" TSRMLS_CC
    );

In practice you should prefer the first variant though. The second form is only useful if you have some misbehaved
extension that forgot to export the class entry.

Just like you can inherit from other classes you can also implement interfaces. For this the variadic
``zend_class_implements()`` functions is used::

    #include "ext/spl/spl_iterators.h"
    #include "zend_interfaces.h"

    zend_class_entry *data_class_ce;

    PHP_METHOD(DataClass, count) { /* ... */ }

    const zend_function_entry data_class_functions[] = {
        PHP_ME(DataClass, count, arginfo_void, ZEND_ACC_PUBLIC)
        /* ... */
        PHP_FE_END
    };

    PHP_MINIT_FUNCTION(test)
    {
        zend_class_entry tmp_ce;
        INIT_CLASS_ENTRY(tmp_ce, "DataClass", data_class_functions);
        data_class_ce = zend_register_internal_class(&tmp_ce TSRMLS_CC);

        /* DataClass implements Countable, ArrayAccess, IteratorAggregate */
        zend_class_implements(
            data_class_ce TSRMLS_CC, 3, spl_ce_Countable, zend_ce_arrayaccess, zend_ce_aggregate
        );

        return SUCCESS;
    }

As you can see ``zend_class_implements()`` takes the class entry, TSRMLS_CC, the number of interfaces to implement and
then the class entries of the interfaces. E.g. if you wanted to additionally implement ``Serializable``::

    zend_class_implements(
        data_class_ce TSRMLS_CC, 4,
        spl_ce_Countable, zend_ce_arrayaccess, zend_ce_aggregate, zend_ce_serializable
    );

You can obviously also create your own interfaces. Interfaces are registered in the same way as classes are, but using
the ``zend_register_internal_interface()`` function and declaring all methods as abstract. E.g. if you wanted to create a
new ``ReversibleIterator`` interface that extends ``Iterator`` and additionally specifies a ``prev`` method, this is how
you would do it::

    #include "zend_interfaces.h"

    zend_class_entry *reversible_iterator_ce;

    const zend_function_entry reversible_iterator_functions[] = {
        PHP_ABSTRACT_ME(ReversibleIterator, prev, arginfo_void)
        PHP_FE_END
    };

    PHP_MINIT_FUNCTION(test)
    {
        zend_class_entry tmp_ce;
        INIT_CLASS_ENTRY(tmp_ce, "ReversibleIterator", reversible_iterator_functions);
        reversible_iterator_ce = zend_register_internal_interface(&tmp_ce TSRMLS_CC);

        /* ReversibleIterator extends Iterator. For interface inheritance the zend_class_implements()
         * function is used. */
        zend_class_implements(reversible_iterator_ce TSRMLS_CC, 1, zend_ce_iterator);

        return SUCCESS;
    }

Internal interfaces have a bit of additional power that userland interfaces don't have - but I'll leave that for a bit
later.
