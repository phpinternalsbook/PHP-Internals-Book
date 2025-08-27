.. _zend_strings:

The zend_string API
===================

Strings in C are usually represented as null-terminated ``char *`` pointers. As PHP supports strings that contain
null bytes, PHP needs to explicitly store the length of the string. Additionally, PHP needs strings to fit into its
general framework of reference-counted structures. This is the purpose of the ``zend_string`` type.

Structure
---------

A ``zend_string`` has the following structure::

    struct _zend_string {
        zend_refcounted_h gc;
        zend_ulong        h;
        size_t            len;
        char              val[1];
    };

Like many other structures in PHP, it embeds a ``zend_refcounted_h`` header, which stores the
:ref:`reference count <refcounting>`, as well as some flags.

The actual character content of the string is stored using the so called "struct hack": The string content is
appended to the end of the structure. While it is declared as ``char[1]``, the actual size is determined dynamically.
This means that the ``zend_string`` header and the string contents are combined into a single allocation, which is
more efficient than using two separate ones. You will find that PHP uses the struct hack in quite a number of places
where a fixed-size header is combined with a dynamic amount of data.

The length of the string is stored explicitly in the ``len`` member. This is necessary to support strings that
contain null bytes, and is also good for performance, because the string lengths does not need to be constantly
recalculated. It should be noted that while ``len`` stores the length without a trailing null byte, the actual
string contents in ``val`` must always contain a trailing null byte. The reason is that there are quite a few C APIs
that accept a null-terminated string, and we want to be able to use these APIs without creating a separate
null-terminated copy of the string.  To give an example, the PHP string ``"foo\0bar"`` would be stored with
``len = 7``, but ``val = "foo\0bar\0"``.

Finally, the string stores a cache of the hash value ``h``, which is used when using strings as
:doc:`hashtable <../hashtables>` keys. It starts with value ``0`` to indicate that the hash has not been computed
yet, while the real hash is computed on first use.

String accessors
----------------

Just like with :ref:`zvals <zvals>`, you don't manipulate ``zend_string`` fields by hand but use a number of access
macros instead::

    zend_string *str = zend_string_init("foo", strlen("foo"), 0);
    php_printf("This is my string: %s\n", ZSTR_VAL(str));
    php_printf("It is %zd char long\n", ZSTR_LEN(str)); // %zd is the printf format for size_t
    zend_string_release(str);

The two most important ones are ``ZSTR_VAL()``, which returns the string contents as ``char *``, and ``ZSTR_LEN()``,
which returns the string length as ``size_t``.

The naming of these macros is slightly unfortunate in that both ``ZSTR_VAL``/``ZSTR_LEN``, as well as
``Z_STRVAL``/``Z_STRLEN`` exist, and both only differ by the position of the underscore. Remember that ``ZSTR_*``
macros work on ``zend_string``, while ``Z_`` macros work on ``zval``::

    zval val;
    ZVAL_STRING(&val, "foo");

    // Z_STRLEN, Z_STRVAL work on zval.
    php_printf("string(%zd) \"%s\"\n", Z_STRLEN(val), Z_STRVAL(val));

    // ZSTR_LEN, ZSTR_VAL work on zend_string.
    zend_string *str = Z_STR(val);
    php_printf("string(%zd) \"%s\"\n", ZSTR_LEN(str), ZSTR_VAL(str));

    zval_ptr_dtor(&val);

The hash value cache of the string can be accessed using ``ZSTR_H()``. However, this accesses the raw cache, which
will be zero if the hash has not been computed yet. Instead, ``ZSTR_HASH()`` or ``zend_string_hash_val()`` should be
used to either get the pre-cached hash, or compute it. In the very rare case where a string is modified after initial
construction, it is possible to discard the cached value using ``zend_string_forget_hash_val()``.

Memory management
-----------------

While we already know how to :ref:`initialize string zvals <initializing_zvals>`, the only direct string creation
API that has been introduced until now is ``zend_string_init()``, which is used to create a ``zend_string`` from an
existing string and length.

The most fundamental string creation function on which all others are based is ``zend_string_alloc()``::

    size_t len = 40;
    zend_string *str = zend_string_alloc(len, /* persistent */ 0);
    for (size_t i = 0; i < len; i++) {
        ZSTR_VAL(str)[i] = 'a';
    }
    // Don't forget to null-terminate!
    ZSTR_VAL(str)[len] = '\0';

This function allocates a string of a certain length (as always, the length does not include the trailing null byte),
and leaves its initialization to you. Like all string allocation functions, it accepts a parameter that determines
whether to use the per-request allocator, or the persistent one.

The ``zend_string_safe_alloc(n, m, l, persistent)`` function allocates a string of length ``n * m + l``. This
function is commonly useful for encoding changes. For example, this is how we could hex encode a string::

    zend_string *convert_to_hex(zend_string *orig_str) {
        zend_string *hex_str = zend_string_safe_alloc(2, ZSTR_LEN(orig_str), 0, /* persistent */ 0);
        char *p = ZSTR_VAL(str);
        for (size_t i = 0; i < ZSTR_LEN(orig_str), i++) {
            const char *to_hex = "0123456789abcdef";
            unsigned char c = ZSTR_VAL(orig_str)[i];
            *p++ = to_hex[c >> 4];
            *p++ = to_hex[c & 0xf];
        }
        *p = '\0';
        return hex_str;
    }

Why can't we simply use ``zend_string_alloc(2 * ZSTR_LEN(orig_str), 0)`` instead? The reason is that the
``zend_string_safe_alloc()`` function will make sure that the ``n * m + l`` calculation does not overflow. For
example, if you are on a 32-bit system, and the string is exactly 2GB large, then multiplying the length by two will
overflow and result in a zero length. The following code will exceed the bounds of the allocation and corrupt
unrelated memory. The ``zend_string_safe_alloc()`` API detects this situation and throws a fatal error in this case.

It is also possible to change the size of a string using ``zend_string_realloc()`` and its variations::

    zend_string *zend_string_realloc(zend_string *s, size_t len, bool persistent);
    // Requires new length larger old length.
    zend_string *zend_string_extend(zend_string *s, size_t len, bool persistent);
    // Requires new length smaller new length.
    zend_string *zend_string_truncate(zend_string *s, size_t len, bool persistent)
    // n * m + l safe variant of zend_string_realloc.
    zend_string *zend_string_safe_realloc(zend_string *s, size_t n, size_t m, size_t l, bool persistent);

As strings are refcounted structures, the realloc functions also take the refcount into account. While this is not
how these functions are implemented, their semantics are equivalent to doing something like this::

    zend_string *new_str = zend_string_init(ZSTR_VAL(s), ZSTR_LEN(s), persistent);
    zend_string_release(s);
    return new_str;

That is, these functions release the string passed to them, but it is safe to use them with shared (or immutable)
strings. If the strings is shared, the refcount is decremented, but the string is not destroyed.

This also brings us to the next topic: refcount management. Rather than using raw ``GC_*`` macros, the
``zend_string`` API contains two helpers to increase the refcount::

    zend_string_addref(str);
    return str;

    // More compact:
    return zend_string_copy(str);

Unlike ``GC_ADDREF()``, the ``zend_string_addref()`` function will handle immutable strings properly. However, the
function that is used most often by far is ``zend_string_copy()``. This function not only increments the refcount,
but also returns the original string. This makes code more readable in practice.

While a ``zend_string_dup()`` function that performs an actual copy of the string (rather than only a refcount
increment) also exists, the behavior is often considered confusing, because it only copies non-immutable strings.
If you want to force a copy of a string, you are better off creating a new one using ``zend_string_init()``.

If the duplication is for the purpose of modifying an already existing string, ``zend_string_separate()`` can be
used instead::

    zend_string *modify_char(zend_string *orig_str) {
        zend_string *str = zend_string_separate(orig_str, /* persistent */ 0);
        ZEND_ASSERT(ZSTR_LEN(str) > 0);
        ZSTR_VAL(str)[0] = 'A';
        return str;
    }

Just like the general zval separation concept, this will return the original string (with discarded hash cache) if it
has a refcount of one, and is thus uniquely owned, and will create a copy otherwise.

Finally, strings needs to be released when no longer used. You are already familiar with the ``zend_string_release()``
API, which will decrement the refcount, and free the string if it drops to zero. You are well served by using only
this function.

However, you may also encounter a number of optimized variations. The most common is ``zend_string_release_ex()``,
which allows you to specify whether the passed string is persistent or non-persistent::

    zend_string_release_ex(str, /* persistent */ 0);

Normally, this would be determined base on the string flags. This avoids the runtime check, and generates less code.
Finally, there are two more functions that only work on strings with refcount one::

    // Requires refcount 1 or immutable.
    zend_string_free(str);
    // Requires refcount 1 and not immutable.
    zend_string_efree(str);

You should avoid using these functions, as it is easy to introduce critical bugs when some API changes from returning
new strings to reusing existing ones.

Other operations
----------------

The ``zend_string`` API supports a few additional operations. The most common one is comparing strings::

    zend_string *foo = zend_string_init("foo", sizeof("foo")-1, 0);
    zend_string *FOO = zend_string_init("FOO", sizeof("FOO")-1, 0);

    // Case-sensitive comparison between zend_strings.
    bool result = zend_string_equals(foo, FOO); // false
    // Case-insensitive comparison between zend_strings.
    bool result = zend_string_equals_ci(foo, FOO); // true

    // Case-sensitive comparison with a string literal.
    bool result = zend_string_equals_literal(foo, "FOO"); // false
    // Case-insensitive comparison with a string literal.
    bool result = zend_string_equals_literal_ci(foo, "FOO"); // true

    zend_string_release(foo);
    zend_string_release(FOO);

There are also helpers to concatenate two or three strings. If you need to concatenate more strings, you should use
the ``smart_str`` API discussed in the next chapter instead.

::

    zend_string *foo = zend_string_init("foo", sizeof("foo")-1, 0);
    zend_string *bar = zend_string_init("bar", sizeof("bar")-1, 0);

    // Creates "foobar"
    zend_string *foobar = zend_string_concat2(
        ZSTR_VAL(foo), ZSTR_LEN(foo),
        ZSTR_VAL(bar), ZSTR_LEN(bar));
    // Creates "foo::bar"
    zend_string *foo_bar = zend_string_concat3(
        ZSTR_VAL(foo), ZSTR_LEN(foo),
        "::", sizeof("::")-1,
        ZSTR_VAL(bar), ZSTR_LEN(bar));

    zend_string_release(foo);
    zend_string_release(bar);
    zend_string_release(foobar);
    zend_string_release(foo_bar);

As you can see, these APIs accept pairs of ``char *`` and lengths, rather than ``zend_string`` structures. This
allows parts of the concatenation to be provided using string literals, without having to allocate a ``zend_string``
for them.

Finally, the ``zend_string_tolower()`` API can be used to lower-case a string::

    zend_string *FOO = zend_string_init("FOO", sizeof("FOO")-1, 0);
    zend_string *foo = zend_string_tolower(FOO);
    zend_string_release(foo);
    zend_string_release(FOO);

The lower-casing uses ASCII rules and is not locale dependent. It is commonly used as a way to make hashtable keys
case-insensitive.

Interned strings
----------------

Just a quick word here about `interned strings <https://en.wikipedia.org/wiki/String_interning>`_. You could 
need such a concept in extension development. Interned strings also interact with opcache extension.

Interned strings are deduplicated strings. When used with opcache, they also get reused from request to request.

Say you want to create the string "foo". What you tend to do is simply create a new string "foo"::

    zend_string *foo;
    foo = zend_string_init("foo", strlen("foo"), 0);

    /* ... */

But a question arises : Hasn't that piece of string already been created before you need it?
When you need a string, you code is executed at some point in PHP's life, that means that some piece of code happening
before yours may have needed the exact same piece of string ("foo" for our example).

Interned strings is about asking the engine to probe the interned strings store, and reuse the already allocated pointer
if it could find your string. If not : create a new string and "intern" it, that is make it available to other parts
of PHP source code (other extensions, the engine itself, etc...).

Here is an example::

    zend_string *foo;
    foo = zend_string_init("foo", strlen("foo"), 0);

    foo = zend_new_interned_string(foo);

    php_printf("This string is interned : %s", ZSTR_VAL(foo));

    zend_string_release(foo);

What we do in the code above, is we create a new ``zend_string`` very classically. Then, we pass that created
``zend_string`` to ``zend_new_interned_string()``. This function looks for the same piece of string ("foo" here) into
the engine interned string buffer. If it finds it (meaning someone already created such a string), it then releases
your string (probably freeing it) and replaces it with the string from the interned string buffer. If it does not find it:
it adds it to the interned string buffer and so makes it available for future usage or other parts of PHP.

You must take care about memory allocation. Interned strings always have a refcount set to one, because they don't need
to be refcounted, as they will get shared with the interned strings buffer, and thus they can't be destroyed out of it.

Example::

    zend_string *foo, *foo2;

    foo  = zend_string_init("foo", strlen("foo"), 0);
    foo2 = zend_string_copy(foo); /* increments refcount of foo */

     /* foo points to the interned string buffer, and refcount
      * in original zend_string falls back to 1 */
    foo = zend_new_interned_string(foo);

    /* This doesn't do anything, as foo is interned */
    zend_string_release(foo);

    /* The original buffer referenced by foo2 is released */
    zend_string_release(foo2);

    /* At the end of the process, PHP will purge its interned
      string buffer, and thus free() our "foo" string itself */

It's all about garbage collection.

When a string is interned, its GC flags are changed to add the ``IS_STR_INTERNED`` flag, whatever the memory allocation
class they use (permanent or request based).
This flag is probed when you want to copy or release a string. If the string is interned, the engine does not increment
its refcount as you copy the string. But it doesn't decrement it nor free it if you release the string. It shadowly
does nothing. At the end of the process lifetime, it will destroy its interned strings buffer, and it will free your
interned strings.

This process is in fact a little bit more complex than this. If you make use of an interned string out of a 
:doc:`request processing <../../extensions_design/php_lifecycle>`, that string will be interned for sure.
However, if you make use of an interned string as PHP is treating a request, then this string will only get interned for 
the current request, and will get cleared after that.
All this is valid if you don't use the opcache extension, something you shouldn't do : use it.

When using the opcache extension, if you make use of an interned string out of a 
:doc:`request processing <../../extensions_design/php_lifecycle>`, that string will be 
interned for sure and will also be shared to every PHP process or thread that will be spawned by you parallelism layer.
Also, if you make use of an interned string as PHP is treating a request, this string will also get interned by opcache 
itself, and shared to every PHP process or thread that will be spawned by you parallelism layer.

Interned strings mechanisms are then changed when opcache extension fires in. Opcache not only allows to intern strings 
that come from a request, but it also allows to share them to every PHP process of the same pool. This is done using 
shared memory. When saving an interned string, opcache will also add the ``IS_STR_PERMANENT`` flag to its GC info. 
That flag means the memory allocation used for the structure (``zend_string`` here) is permanent, it could be a shared 
read-only memory segment.

Interned strings save memory, because the same string is never stored more than once in memory. But it could waste some
CPU time as it often needs to lookup the interned strings store, even if that process is well optimized yet.
As an extension designer, here are global rules:

* If opcache is used (it should be), and if you need to create read-only strings : use an interned string.
* If you need a string you know for sure PHP will have interned (a well-known-PHP-string, f.e "php" or "str_replace"),
  use an interned string.
* If the string is not read-only and could/should be altered after its been created, do not use an interned string.
* If the string is unlikely to be reused in the future, do not use an interned string.

.. warning:: Never ever try to modify (write to) an interned string, you'll likely crash.

Interned strings are detailed in `Zend/zend_string.c <https://github.com/php/php-src/blob/PHP-7.0/Zend/zend_string.c>`_

..
    ZSTR_EMPTY_ALLOC
    ZSTR_CHAR
    ZSTR_KNOWN
    zend_string_init_fast
    zend_new_interned_string
    zend_string_init_interned
