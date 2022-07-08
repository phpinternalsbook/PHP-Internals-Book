smart_str API
=============

That may seem strange, but the C language offers nearly nothing to play with strings (build, concatenate, shrink,
expand, transform, etc...). C is a low level general purpose language one can use to build APIs to deal with more
specific tasks, such as string constructions.

.. note:: Obviously you all got that we talk about ASCII strings, aka bytes. No Unicode in there.

PHP's ``smart_str`` is an API that will help you build strings and especially concatenate chunks of bytes into strings.
This API seats next to :doc:`PHP's special printf() APIs<printing_functions>` and :doc:`zend_string <zend_strings>` to
help with strings management.

smart_str VS smart_string
*************************

Here are the two structures::

    typedef struct {
        char *c;
        size_t len;
        size_t a;
    } smart_string;

    typedef struct {
        zend_string *s;
        size_t a;
    } smart_str;

Like you can see, one will work with traditional C strings (as ``char*/size_t``) and the other will make use of the
PHP's specific ``zend_string`` structure.

We will detail the latter: ``smart_str``, that works with :doc:`zend_strings <zend_strings>`. Both APIs are exactly the
same, simply note that one (the one we'll detail here) starts by ``smart_str_**()`` and the other by 
``smart_string_***()``. Don't confuse !

The ``smart_str`` API is detailed into `Zend/zend_smart_str.h
<https://github.com/php/php-src/blob/509f5097ab0b578adc311c720afcea8de266aadd/Zend/zend_smart_str.h>`_ (also the .c
file).

.. warning:: ``smart_str`` is not to be confused with ``smart_string``.

Basic API usage
***************

So far so good, that API is really easy to manage. You basically stack-allocate a ``smart_str``, and pass its pointer to
``smart_str_***()`` API functions that manage the embedded ``zend_string`` for you. You build your string, use it, and
then you free it. Nothing very strong in there right ?

The embedded ``zend_string`` will be allocated whether
:doc:`permanently or request-bound <../../memory_management/zend_memory_manager>`, that depends on the last extended API
parameter you'll use::

    smart_str my_str = {0};

    smart_str_appends(&my_str, "Hello, you are using PHP version ");
    smart_str_appends(&my_str, PHP_VERSION);

    smart_str_appendc(&my_str, '\n');

    smart_str_appends(&my_str, "You are using ");
    smart_str_append_unsigned(&my_str, zend_hash_num_elements(CG(function_table)));
    smart_str_appends(&my_str, " PHP functions");

    smart_str_0(&my_str);

    /* Use my_str now */
    PHPWRITE(ZSTR_VAL(my_str.s), ZSTR_LEN(my_str.s));

    /* Don't forget to release/free it */
    smart_str_free(&my_str);

We can also use the embedded ``zend_string`` independently of the ``smart_str``::

    smart_str my_str = {0};

    smart_str_appends(&my_str, "Hello, you are using PHP version ");
    smart_str_appends(&my_str, PHP_VERSION);

    zend_string *str = smart_str_extract(my_str);
    RETURN_STRING(str);

    /* We don't need to free my_str in this case */

``smart_str_extract()`` returns a pre-allocated empty string if ``smart_str.s``
is ``NULL``. Otherwise, it adds a trailing *NUL* byte and trims the allocated
memory to the string size.

We used here the simple API, the extended one ends with ``_ex()``, and allows you to tell if you want a persistent or
a request-bound allocation for the underlying ``zend_string``. Example::

    smart_str my_str = {0};

    smart_str_appends_ex(&my_str, "Hello world", 1); /* 1 means persistent allocation */

Then, depending on what you want to append, you'll use the right API call. If you append a classical C string, you can
use ``smart_str_appends(smart_str *dst, const char *src)``. If you make use of a binary string, and thus know its
length, then use ``smart_str_appendl(smart_str *dst, const char *src, size_t len)``.

The less specific ``smart_str_append(smart_str *dest, const zend_string *src)`` simply appends a ``zend_string`` to
your ``smart_str`` string. And if you come to play with others ``smart_str``, use
``smart_str_append_smart_str(smart_str *dst, const smart_str *src)`` to combine them together.

smart_str specific tricks
*************************

* Never forget to finish your string with a call to ``smart_str_0()``. That puts a *NUL* char at the end of the embed
  string and make it compatible with libc string functions.
* Never forget to free your string, with ``smart_str_free()``, once you're done with it.
* Use ``smart_str_extract()`` to get a standalone ``zend_string`` when you have
  finished building the string. This takes care of calling ``smart_str_0()``,
  and of optimizing allocations. In this case, calling ``smart_str_free()`` is
  not necessary.
* You can share the standalone ``zend_string`` later elsewhere playing with its reference
  counter. Please, visit the :doc:`zend_string dedicated chapter <zend_strings>` to know more about it.
* You can play with ``smart_str`` allocations. Look at ``smart_str_alloc()`` and friends.
* ``smart_str`` is heavily used into PHP's heart. For example, PHP's
  :doc:`specific printf() functions <printing_functions>` internally use a ``smart_str`` buffer.
* ``smart_str`` is definitely an easy structure you need to master.

