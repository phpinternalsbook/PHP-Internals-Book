Streams
=======

Overview
--------

The PHP Streams API introduces a unified approach to the handling of
files and sockets in PHP extension.  Using a single API with standard
functions for common operations, the streams API allows your extension
to access files, sockets, URLs, memory and script-defined objects.
Streams is a run-time extensible API that allows dynamically loaded
modules (and scripts!) to register new streams.

The aim of the Streams API is to make it comfortable for developers to
open files, URLs and other streamable data sources with a unified API
that is easy to understand.  The API is more or less based on the ANSI
C stdio family of functions (with identical semantics for most of the main
functions), so C programmers will have a feeling of familiarity with streams.

The streams API operates on a couple of different levels: at the base level,
the API defines php_stream objects to represent streamable data sources.
On a slightly higher level, the API defines php_stream_wrapper objects
which "wrap" around the lower level API to provide support for retrieving
data and meta-data from URLs.  An additional ``context``
parameter, accepted by most stream creation functions, is passed to the
wrapper's ``stream_opener`` method to fine-tune the behavior
of the wrapper.

Any stream, once opened, can also have any number of ``filters``
applied to it, which process data as it is read from/written to the stream.

Streams can be cast (converted) into other types of file-handles, so that they
can be used with third-party libraries without a great deal of trouble.  This
allows those libraries to access data directly from URL sources.  If your
system has the ``fopencookie`` or
``funopen`` function, you can even
pass any PHP stream to any library that uses ANSI stdio!

Streams Basics
--------------

Using streams is very much like using ANSI stdio functions.  The main
difference is in how you obtain the stream handle to begin with.
In most cases, you will use ``php_stream_open_wrapper``
to obtain the stream handle.  This function works very much like fopen,
as can be seen from the example below:

Simple stream example that displays the PHP home page::

    php_stream * stream = php_stream_open_wrapper("http://www.php.net", "rb", REPORT_ERRORS, NULL);
    if (stream) {
        while(!php_stream_eof(stream)) {
            char buf[1024];
            
            if (php_stream_gets(stream, buf, sizeof(buf))) {
                printf(buf);
            } else {
                break;
            }
        }
        php_stream_close(stream);
    }

The table below shows the Streams equivalents of the more common ANSI stdio functions.
Unless noted otherwise, the semantics of the functions are identical.

ANSI stdio equivalent functions in the Streams API

+---------------------+-------------------------+------------------------------------------------------+
+ ANSI Stdio Function + PHP Streams Function    + Notes                                                +
+=====================+=========================+======================================================+
+ fopen               + php_stream_open_wrapper + Streams includes additional parameters               +
+---------------------+-------------------------+------------------------------------------------------+
+ fclose              + php_stream_close        +                                                      +
+---------------------+-------------------------+------------------------------------------------------+
+ fgets               + php_stream_gets         +                                                      +
+---------------------+-------------------------+------------------------------------------------------+
+ fread               + php_stream_read         + The nmemb parameter is assumed to have a value of 1, +
+                     +                         + so the prototype looks more like read(2)             +
+---------------------+-------------------------+------------------------------------------------------+
+ fwrite              + php_stream_write        + The nmemb parameter is assumed to have a value of 1, +
+                     +                         + so the prototype looks more like write(2)            +
+---------------------+-------------------------+------------------------------------------------------+
+ fseek               + php_stream_seek         +                                                      +
+---------------------+-------------------------+------------------------------------------------------+
+ ftell               + php_stream_tell         +                                                      +
+---------------------+-------------------------+------------------------------------------------------+
+ rewind              + php_stream_rewind       +                                                      +
+---------------------+-------------------------+------------------------------------------------------+
+ feof                + php_stream_eof          +                                                      +
+---------------------+-------------------------+------------------------------------------------------+
+ fgetc               + php_stream_getc         +                                                      +
+---------------------+-------------------------+------------------------------------------------------+
+ fputc               + php_stream_putc         +                                                      +
+---------------------+-------------------------+------------------------------------------------------+
+ fflush              + php_stream_flush        +                                                      +
+---------------------+-------------------------+------------------------------------------------------+
+ puts                + php_stream_puts         + Same semantics as puts, NOT fputs                    +
+---------------------+-------------------------+------------------------------------------------------+
+ fstat               + php_stream_stat         + Streams has a richer stat structure                  +
+---------------------+-------------------------+------------------------------------------------------+

Streams as Resources
--------------------

All streams are registered as resources when they are created.  This ensures
that they will be properly cleaned up even if there is some fatal error.
All of the filesystem functions in PHP operate on streams resources - that
means that your extensions can accept regular PHP file pointers as
parameters to, and return streams from their functions.
The streams API makes this process as painless as possible:

How to accept a stream as a parameter::

    PHP_FUNCTION(example_write_hello)
    {
        zval *zstream;
        php_stream *stream;
        
        if (FAILURE == zend_parse_parameters(ZEND_NUM_ARGS() TSRMLS_CC, "r", &zstream))
            return;
        
        php_stream_from_zval(stream, &zstream);

        /* you can now use the stream.  However, you do not "own" the
            stream, the script does.  That means you MUST NOT close the
            stream, because it will cause PHP to crash! */

        php_stream_write(stream, "hello\n");
            
        RETURN_TRUE();
    }

How to return a stream from a function::

    PHP_FUNCTION(example_open_php_home_page)
    {
        php_stream *stream;
        
        stream = php_stream_open_wrapper("http://www.php.net", "rb", REPORT_ERRORS, NULL);
        
        php_stream_to_zval(stream, return_value);

        /* after this point, the stream is "owned" by the script.
            If you close it now, you will crash PHP! */
    }

Since streams are automatically cleaned up, it's tempting to think that we can get
away with being sloppy programmers and not bother to close the streams when we
are done with them.  Although such an approach might work, it is not a good idea
for a number of reasons: streams hold locks on system resources while they are
open, so leaving a file open after you have finished with it could prevent other
processes from accessing it.  If a script deals with a large number of files,
the accumulation of the resources used, both in terms of memory and the
sheer number of open files, can cause web server requests to fail.  Sounds
bad, doesn't it?  The streams API includes some magic that helps you to
keep your code clean - if a stream is not closed by your code when it should
be, you will find some helpful debugging information in you web server error
log.

.. note::
    Always use a debug build of PHP when developing an extension
    (``--enable-debug`` when running configure), as a lot of
    effort has been made to warn you about memory and stream leaks.

In some cases, it is useful to keep a stream open for the duration of a request,
to act as a log or trace file for example.  Writing the code to safely clean up
such a stream is not difficult, but it's several lines of code that are not
strictly needed.  To save yourself the trouble of writing the code, you
can mark a stream as being OK for auto cleanup.  What this means is
that the streams API will not emit a warning when it is time to auto-cleanup
a stream.  To do this, you can use ``php_stream_auto_cleanup``.

.. toctree::
    :maxdepth: 2

    streams/common.rst
    streams/dir.rst
    streams/file.rst
    streams/socket.rst
    streams/structs.rst
    streams/constants.rst
