#Date Parser

[![Dub](https://img.shields.io/dub/v/dateparser.svg)](http://code.dlang.org/packages/dateparser) [![Coverage Status](https://coveralls.io/repos/github/JackStouffer/date-parser/badge.svg?branch=master)](https://coveralls.io/github/JackStouffer/date-parser?branch=master)

[Docs](https://jackstouffer.github.io/date-parser/)

A port of the Python Dateutil date parser. This module offers a generic date/time string parser which is able to parse most known formats to represent a date and/or time. This module attempts to be forgiving with regards to unlikely input formats, returning a SysTime object even for dates which are ambiguous.

Compiles with D versions 2.068 and up. Tested with ldc v0.17.0 and dmd v2.068.2 - v2.070.2.

In order to use this with LDC v0.17.0 and DMD 2.068, you must download and compile this manually due to the fact that DUB has no way to specify dependencies for specific versions or compilers.

##Install With Dub

```
{
    ...
    "dependencies": {
        "dateparser": "~>1.1.0"
    }
}
```

## Simple Example

View the docs for more.

```
import std.datetime;
import dateparser;

void main()
{
    assert(parse("2003-09-25") == SysTime(DateTime(2003, 9, 25)));
}
```

## Speed

Based on `master`

String | Python | LDC | DMD
------ | ------ | --- | ---
Thu Sep 25 10:36:28 BRST 2003 | 156 µs | 17 μs | 24 μs
2003-09-25T10:49:41.5-03:00 | 136 µs | 7 μs | 12 μs
09.25.2003 | 124 µs | 13 μs | 20 μs
2003-09-25 | 66.4 µs | 9 μs | 10 μs
