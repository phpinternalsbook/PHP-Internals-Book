PHP's custom printf functions
=============================

You all know libc's ``printf()`` and family. This chapter will detail those many clones PHP declares and use, what's
their goal, why use them and when to use them.

.. note:: Libc's documentation about ``printf()`` and friends
          `is located here <https://www.gnu.org/software/libc/manual/html_node/Formatted-Output-Functions.html>`_

You know that those functions are useful, but sometimes don't provide enough functionalities.
Also, you know that
`adding format strings <https://www.gnu.org/software/libc/manual/html_node/Customizing-Printf.html>`_ to ``printf()``
family is not trivial, not portable and security risky.

PHP adds its own printf-like functions to replace libc ones and to be used by the internal developer.
They will mainly add new formats, play with :doc:`zend_string<zend_strings>` instead of
``char *``, etc...  Let's see them together.

.. warning:: You must master your libc default ``printf()`` formats. Read
             `their documentation here <http://www.cplusplus.com/reference/cstdio/printf/>`_.

.. note::  Those functions are added **to replace** libc ones, that means that if you use ``sprintf()`` f.e, that won't
           lead to libc's ``sprintf()``, but to PHP replacement. Except the traditional ``printf()``, everything else
           is replaced.

Traditional use
***************

First of all, you should not use ``sprintf()``, as that function doesn't perform any check and allows many buffer
overflow errors. Please, try to avoid using it.

.. warning:: Please try to avoid using ``sprintf()`` as much as possible.

Then, you have some choice.

You know your result buffer size
--------------------------------

If you know your buffer size, ``snprintf()`` or ``slprintf()`` will do the job for you. There is a difference in what
those functions return, but not in what those functions do.

They both print according to the formats passed, and they both terminate your buffer by a ``NUL`` byte *'\\0'* whatever
happens. However, ``snprintf()`` returns the number of characters that could have been used, whereas ``slprintf()``
returns the number of characters that have effectively been used, thus enabling to detect too-small buffers and string
truncation. This, is not counting the final *'\\0'*.

Here is an example so that you fully understand::

    char foo[8]; /* 8-char large buffer */
    const char str[] = "Hello world"; /* 12 chars including \0 in count */
    int r;

    r = snprintf(foo, sizeof(foo), "%s", str);
    /* r = 11 here even if only 7 printable chars were written in foo */

    /* foo value is now 'H' 'e' 'l' 'l' 'o' ' ' 'w' '\0' */

``snprintf()`` is not a good function to use, as it does not allows to detect an eventual string truncation.
As you can see from the example above, "Hello world\\0" doesn't fit in an eight-byte buffer, that's obvious, but
``snprintf()`` still returns you 11, which is ``strlen("Hello world\0")``. You have no way to detect that the string's
got truncated.

Here is ``slprintf()``::

    char foo[8]; /* 8-char large buffer */
    const char str[] = "Hello world"; /* 12 chars including \0 in count */
    int r;

    r = slprintf(foo, sizeof(foo), "%s", str);
    /* r = 7 here , because 7 printable chars were written in foo */

    /* foo value is now 'H' 'e' 'l' 'l' 'o' ' ' 'w' '\0' */

With ``slprintf()``, the result buffer ``foo`` contains the exact same string, but the returned value is now 7. 7 is
less than the 11 chars from the *"Hello world"* string, thus you can detect that it got truncated::

    if (slprintf(foo, sizeof(foo), "%s", str) < strlen(str)) {
        /* A string truncation occurred */
    }

Remember:

* Those two function always ``NUL`` terminate the string, truncation or not. Result strings are then safe C strings.
* Only ``slprintf()`` allows to detect a string truncation.

Those two functions are defined in
`main/snprintf.c <https://github.com/php/php-src/blob/648be8600ff89e1b0e4a4ad25cebad42b53bed6d/main/snprintf.c>`_

You don't know your buffer size
-------------------------------

Now if you don't know your result buffer size, you need a dynamicaly allocated one, and then you'll use ``spprintf()``.
Remember that **you'll have to free** the buffer by yourself !

Here is an example::

    #include <time.h>

    char *result;
    int r;

    time_t timestamp = time(NULL);

    r = spprintf(&result, 0, "Here is the date: %s", asctime(localtime(&timestamp)));

    /* now use result that contains something like "Here is the date: Thu Jun 15 19:12:51 2017\n" */

    efree(result);

``spprintf()`` returns the number of characters that've been printed into the result buffer, not counting the final
*'\\0'*, hence you know the number of bytes that got allocated for you (minus one).

Please, note that the allocation is done using ZendMM (request allocation), and should thus be used as part of a
request and freed using ``efree()`` and not ``free()``.

.. note:: :doc:`The chapter about Zend Memory Manager <../../memory_management/zend_memory_manager>` (ZendMM) details
          how dynamic memory is allocated through PHP.

If you want to limit the buffer size, you pass that limit as the second argument, if you pass *0*, that means
unlimited::

    #include <time.h>

    char *result;
    int r;

    time_t timestamp = time(NULL);

    /* Do not print more than 10 bytes || allocate more than 11 bytes */
    r = spprintf(&result, 10, "Here is the date: %s", asctime(localtime(&timestamp)));

    /* r == 10 here, and 11 bytes were allocated into result */

    efree(result);

.. note:: Whenever possible, try not to use dynamic memory allocations. That impacts performances. If you got the
          choice, go for the static stack allocated buffer.

``spprintf()`` is written in
`main/spprintf.c <https://github.com/php/php-src/blob/648be8600ff89e1b0e4a4ad25cebad42b53bed6d/main/spprintf.c>`_.

What about printf() ?
---------------------

If you need to ``printf()``, aka to print formatted to the output stream, use ``php_printf()``. That function
internally uses ``spprintf()``, and thus performs a dynamic allocation that it frees itself just after having sent it
to the SAPI output, aka stdout in case of CLI, or the output buffer (CGI buffer f.e) for other SAPIs.

Special PHP printf formats
--------------------------

Remember that PHP replaces most libc's ``printf()`` functions by its own of its own design. You can have a look at
the argument parsing API which is easy to understand `from reading the source
<https://github.com/php/php-src/blob/509f5097ab0b578adc311c720afcea8de266aadd/main/spprintf.c#L203>`_.

What that means is that arguments parsing algo has been fully rewritten, and may differ from what you're used to in libc.
F.e, the libc locale is not taken care of in most cases.

Special formats may be used, like *"%I64"* to explicitly print to an int64, or *"%I32"*.
You can also use *"%Z"* to make a zval printable (according to PHP cast rules to string), that one is a great addition.

The formatter will also recognize infinite numbers and print "INF", or "NAN" for not-a-number.

If you make a mistake, and ask the formatter to print a ``NULL`` pointer, where libc will crash for sure, PHP will
return *"(null)"* as a result string.

.. note:: If in a printf you see a magic *"(null)"* appearing, that means you passed a NULL pointer to one of PHP
          printf family functions.


Printf()ing into zend_strings
-----------------------------

As :doc:`zend_string <zend_strings>` are a very common structure into PHP source, you may need to ``printf()`` into a
``zend_string`` instead of a traditional C ``char *``.  For this, use ``strpprintf()``.

The API is ``zend_string *strpprintf(size_t max_len, const char *format, ...)`` that means that the ``zend_string`` is
returned to you, and not the number of printed chars as you may expect. You can limit that number though, using the
first parameter (pass 0 to mean infinite); and you must remember that the ``zend_string`` will be allocated using the
Zend Memory Manager, and thus bound to the current request.

Obviously, the format API is shared with the one seen above.

Here is a quick example::

    zend_string *result;

    result = strpprintf(0, "You are using PHP %s", PHP_VERSION);

    /* Do something with result */

    zend_string_release(result);

A note on ``zend_`` API
-----------------------

You may meet ``zend_spprintf()``, or ``zend_strpprintf()`` functions. Those are the exact same as the ones seen above.

They are just here as part of the separation between the Zend Engine and PHP Core, a detail that is not important for
us, as into the source code, everything gets mixed together.
