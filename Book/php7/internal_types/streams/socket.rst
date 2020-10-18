Streams Socket API Reference
----------------------------

php_stream_sock_open_from_socket
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Convert a socket descriptor into a stream::

    php_stream *php_stream_sock_open_from_socket(int socket, int persistent)

``php_stream_sock_open_from_socket`` returns a stream based on the
``socket``. ``persistent`` is a flag that
controls whether the stream is opened as a persistent stream.  Generally speaking, this parameter
will usually be 0.

php_stream_sock_open_host
^^^^^^^^^^^^^^^^^^^^^^^^^

Open a connection to a host and return a stream::

    php_stream *php_stream_sock_open_host(const char *host, unsigned short port, int socktype,
                                          struct timeval *timeout, int persistent)

``php_stream_sock_open_host`` establishes a connect to the specified
``host`` and ``port``. ``socktype``
specifies the connection semantics that should apply to the connection. Values for
``socktype`` are system dependent, but will usually include (at a minimum)
``SOCK_STREAM`` for sequenced, reliable, two-way connection based streams (TCP),
or ``SOCK_DGRAM`` for connectionless, unreliable messages of a fixed maximum
length (UDP).

``persistent`` is a flag the controls whether the stream is opened as a persistent
stream. Generally speaking, this parameter will usually be 0.

If not NULL, ``timeout`` specifies a maximum time to allow for the connection to be made.
If the connection attempt takes longer than the timeout value, the connection attempt is aborted and
NULL is returned to indicate that the stream could not be opened.

.. note::
    The timeout value does not include the time taken to perform a DNS lookup. The reason for this is
    because there is no portable way to implement a non-blocking DNS lookup.

    The timeout only applies to the connection phase; if you need to set timeouts for subsequent read
    or write operations, you should use ``php_stream_sock_set_timeout`` to configure
    the timeout duration for your stream once it has been opened.

The streams API places no restrictions on the values you use for ``socktype``,
but encourages you to consider the portability of values you choose before you release your
extension.

php_stream_sock_open_unix
^^^^^^^^^^^^^^^^^^^^^^^^^

Open a Unix domain socket and convert into a stream::

    php_stream *php_stream_sock_open_unix(const char *path, int pathlen, int persistent, struct timeval *timeout)

``php_stream_sock_open_unix`` attempts to open the Unix domain socket
specified by ``path``.  ``pathlen`` specifies the
length of ``path``.
If ``timeout`` is not NULL, it specifies a timeout period for the connection attempt.
``persistent`` indicates if the stream should be opened as a persistent
stream. Generally speaking, this parameter will usually be 0.

.. note::
    This function will not work under Windows, which does not implement Unix domain sockets.
    A possible exception to this rule is if your PHP binary was built using cygwin.  You are encouraged
    to consider this aspect of the portability of your extension before it's release.

.. note::
    This function treats ``path`` in a binary safe manner, suitable for
    use on systems with an abstract namespace (such as Linux), where the first character
    of path is a NUL character.
