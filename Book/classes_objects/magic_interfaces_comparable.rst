Magic interfaces - Comparable
=============================

Internal interfaces in PHP are very similar to their userland equivalents. The only notable difference is that internal
interfaces have the additional possibility of specifying a handler that is executed when the interface is implemented.
This feature can be used for various purposes like enforcing additional constraints or replacing handlers. We'll make
use of it to implement a "magic" ``Comparable`` interface, which exposes the internal ``compare_objects`` handler to
userland.

The interface itself will look as follows:

.. code-block:: php

    interface Comparable {
        static function compare($left, $right);
    }

First, lets register this new interface in ``MINIT``::

    zend_class_entry *comparable_ce;

    ZEND_BEGIN_ARG_INFO_EX(arginfo_comparable, 0, 0, 2)
        ZEND_ARG_INFO(0, obj1)
        ZEND_ARG_INFO(0, obj2)
    ZEND_END_ARG_INFO()

    const zend_function_entry comparable_functions[] = {
        ZEND_FENTRY(compare, NULL, arginfo_comparable, ZEND_ACC_PUBLIC|ZEND_ACC_ABSTRACT|ZEND_ACC_STATIC)
        PHP_FE_END
    };

    PHP_MINIT_FUNCTION(comparable)
    {
        zend_class_entry tmp_ce;
        INIT_CLASS_ENTRY(tmp_ce, "Comparable", comparable_functions);
        comparable_ce = zend_register_internal_interface(&tmp_ce TSRMLS_CC);

        return SUCCESS;
    }

Note that in this case we can't use ``PHP_ABSTRACT_ME``, because it does not support static abstract methods. Instead
we have to use the low-level ``ZEND_FENTRY`` macro.

Next we implement the ``interface_gets_implemented`` handler::

    static int implement_comparable(zend_class_entry *interface, zend_class_entry *ce TSRMLS_DC)
    {
        if (ce->create_object != NULL) {
            zend_error(E_ERROR, "Comparable interface can only be used on userland classes");
        }

        ce->create_object = comparable_create_object_override;

        return SUCCESS;
    }

    // in MINIT
    comparable_ce->interface_gets_implemented = implement_comparable;

When the interface is implemented the ``implement_comparable`` function will be called. In this function we override the
classes ``create_object`` handler. To simplify things we only allow the interface to be used when ``create_object``
was ``NULL`` previously (i.e. it is a "normal" userland class). We could obviously also make this work with arbitrary
classes by backing up the old ``create_object`` handler somewhere.

In our ``create_object`` override we create the object as usual but assign our own handlers structure with a custom
``compare_objects`` handler::

    static zend_object_handlers comparable_handlers;

    static zend_object_value comparable_create_object_override(zend_class_entry *ce TSRMLS_DC)
    {
        zend_object *object;
        zend_object_value retval;

        retval = zend_objects_new(&object, ce TSRMLS_CC);
        object_properties_init(object, ce);

        retval.handlers = &comparable_handlers;

        return retval;
    }

    // In MINIT
    memcpy(&comparable_handlers, zend_get_std_object_handlers(), sizeof(zend_object_handlers));
    comparable_handlers.compare_objects = comparable_compare_objects;

Lastly we have to implement the custom comparison handler. It will call the ``compare`` method using the
``zend_call_method_with_2_params`` macro, which is defined in ``zend_interfaces.h``. One question that arises is which
class the method should be called on. For this implementation we'll simply use the first passed object, though this is
just an arbitrary choice. In practice this means that for ``$left < $right`` the class of ``$left`` will be used, but
for ``$left > $right`` the class of ``$right`` is used (because PHP transforms the ``>`` to a ``<`` operation).

::

    #include "zend_interfaces.h"

    static int comparable_compare_objects(zval *obj1, zval *obj2 TSRMLS_DC)
    {
        zval *retval = NULL;
        int result;

        zend_call_method_with_2_params(NULL, Z_OBJCE_P(obj1), NULL, "compare", &retval, obj1, obj2);

        if (!retval || Z_TYPE_P(retval) == IS_NULL) {
            if (retval) {
                zval_ptr_dtor(&retval);
            }
            return zend_get_std_object_handlers()->compare_objects(obj1, obj2 TSRMLS_CC);
        }

        convert_to_long_ex(&retval);
        result = ZEND_NORMALIZE_BOOL(Z_LVAL_P(retval));
        zval_ptr_dtor(&retval);

        return result;
    }

The ``ZEND_NORMALIZE_BOOL`` macro used above normalizes the returned integer to ``-1``, ``0`` and ``1``.

And that's all it takes. Now we can try out the new interface (sorry if the example doesn't make particularly much
sense):

.. code-block:: php

    class Point implements Comparable {
        protected $x, $y, $z;

        public function __construct($x, $y, $z) {
            $this->x = $x; $this->y = $y; $this->z = $z;
        }

        /* We assume a point is smaller/greater if all its components are smaller/greater */
        public static function compare($p1, $p2) {
            if ($p1->x == $p2->x && $p1->y == $p2->y && $p1->z == $p2->z) {
                return 0;
            }

            if ($p1->x < $p2->x && $p1->y < $p2->y && $p1->z < $p2->z) {
                return -1;
            }

            if ($p1->x > $p2->x && $p1->y > $p2->y && $p1->z > $p2->z) {
                return 1;
            }

            // not comparable
            return 1;
        }
    }

    $p1 = new Point(1, 1, 1);
    $p2 = new Point(2, 2, 2);
    $p3 = new Point(1, 0, 2);

    var_dump($p1 < $p2, $p1 > $p2, $p1 == $p2); // true, false, false

    var_dump($p1 == $p1); // true

    var_dump($p1 < $p3, $p1 > $p3, $p1 == $p3); // false, false, false

