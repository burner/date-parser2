/**
 * Boost Software License - Version 1.0 - August 17th, 2003
 *
 * Permission is hereby granted, free of charge, to any person or organization
 * obtaining a copy of the software and accompanying documentation covered by
 * this license (the "Software") to use, reproduce, display, distribute,
 * execute, and transmit the Software, and to prepare derivative works of the
 * Software, and to permit third-parties to whom the Software is furnished to
 * do so, all subject to the following:
 *
 * The copyright notices in the Software and this entire statement, including
 * the above license grant, this restriction and the following disclaimer,
 * must be included in all copies of the Software, in whole or in part, and
 * all derivative works of the Software, unless such copies or derivative
 * works are solely in the form of machine-executable object code generated by
 * a source language processor.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE, TITLE AND NON-INFRINGEMENT. IN NO EVENT
 * SHALL THE COPYRIGHT HOLDERS OR ANYONE DISTRIBUTING THE SOFTWARE BE LIABLE
 * FOR ANY DAMAGES OR OTHER LIABILITY, WHETHER IN CONTRACT, TORT OR OTHERWISE,
 * ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 */

module dateparser;

import std.stdio;
import std.array;
import std.datetime;
import std.algorithm.iteration;
import std.traits;
import std.typecons;
import std.range;
static import std.uni;
import std.utf;
import containers;
import std.experimental.allocator.gc_allocator;

pragma(inline, true)
bool isDigit(dchar c) @safe pure nothrow @nogc
{
    return '0' <= c && c <= '9';
}

pragma(inline, true)
bool isWhite(dchar c) @safe pure nothrow @nogc
{
    return c == ' ' || (c >= 0x09 && c <= 0x0D);
}

enum TokenType
{
    Integer,
    Float,
    String,
    Seperator
}

struct Token(Char) if (isSomeChar!Char)
{
    const(Char)[] chars;
    TokenType type;
}

enum LexerState
{
    FindStartOfToken,
    ParseNumber,
    ParseString,
    ParseSeperator
}

auto lex(Allocator, Range)(Range dateStr)
    if (isSomeString!Range || (isRandomAccessRange!Range && hasSlicing!Range && isSomeChar!(ElementEncodingType!Range)))
{
    alias TokenQual = Token!(Unqual!(ElementEncodingType!Range));

    auto tokens = DynamicArray!(TokenQual, Allocator)();
    tokens.reserve(dateStr.length / 2);

    LexerState lexState = LexerState.FindStartOfToken;
    TokenQual currentToken = void;
    size_t tokenStart = 0;
    size_t i = 0;
    size_t sawPeriod = 0;

    static if (isSomeString!Range)
    {
        auto r = dateStr.byCodeUnit.save;
    }
    else
    {
        auto r = dateStr.save;
    }

    while (!r.empty)
    {
        final switch (lexState)
        {
            case LexerState.FindStartOfToken:
            {
                if (isDigit(r.front))
                {
                    lexState = LexerState.ParseNumber;
                    currentToken.type = TokenType.Integer;
                    tokenStart = i;
                }
                else if (r.front == '/' || r.front == ':' || r.front == '-' || r.front == '.' || r.front == ',')
                {
                    lexState = LexerState.ParseSeperator;
                    currentToken.type = TokenType.Seperator;
                    tokenStart = i;
                }
                else if (isWhite(r.front))
                {
                    r.popFront();
                    ++i;
                }
                else
                {
                    lexState = LexerState.ParseString;
                    currentToken.type = TokenType.String;
                    tokenStart = i;
                }
                break;
            }
            case LexerState.ParseString:
            {
                while (!r.empty && std.uni.isAlpha(r.front))
                {
                    r.popFront();
                    ++i;
                }
                lexState = LexerState.FindStartOfToken;
                currentToken.chars = dateStr[tokenStart .. i];
                tokens ~= currentToken;
                break;
            }
            case LexerState.ParseNumber:
            {
                while (!r.empty)
                {
                    if (r.front == '.' && i < r.length - 1 && !isDigit(dateStr[i + 1]))
                    {
                        break;
                    }
                    else if (r.front == '.')
                    {
                        ++sawPeriod;
                    }
                    else if (!isDigit(r.front))
                    {
                        break;
                    }

                    r.popFront();
                    ++i;
                }

                if (sawPeriod == 0)
                {
                    lexState = LexerState.FindStartOfToken;
                    currentToken.chars = dateStr[tokenStart .. i];
                    tokens ~= currentToken;
                }
                else if (sawPeriod == 1)
                {
                    lexState = LexerState.FindStartOfToken;
                    currentToken.type = TokenType.Float;
                    currentToken.chars = dateStr[tokenStart .. i];
                    tokens ~= currentToken;
                }
                else
                {
                    auto splitted = dateStr[tokenStart .. i].splitter!("a == b", Yes.keepSeparators)('.');
                    foreach (str; splitted)
                    {
                        if (str[0] == '.')
                        {
                            currentToken.type = TokenType.Seperator;
                        }
                        else
                        {
                            currentToken.type = TokenType.Integer;
                        }
                        
                        currentToken.chars = str;
                        tokens ~= currentToken;
                    }

                    currentToken = TokenQual.init;
                }

                sawPeriod = 0;
                break;
            }
            case LexerState.ParseSeperator:
            {
                while (!r.empty && (r.front == '/' || r.front == ':' || r.front == '-' || r.front == ','))
                {
                    r.popFront();
                    ++i;
                }
                lexState = LexerState.FindStartOfToken;
                currentToken.chars = dateStr[tokenStart .. i];
                tokens ~= currentToken;
                break;
            }
        }
    }

    return tokens;
}

auto parse(Allocator = GCAllocator, Range)(Range dateStr)
    if (isSomeString!Range || (isRandomAccessRange!Range && hasSlicing!Range && isSomeChar!(ElementEncodingType!Range)))
{
    return lex!Allocator(dateStr);
}

unittest
{
    writeln(parse("Thu Sep 25 10:36:28 BRST 2003")[]);
    writeln(parse("2003-09-25T10:49:41.5-03:00")[]);
    writeln(parse("10.10.2003")[]);
    writeln(parse("Feb 30, 2007")[]);
    //writeln(parse("09-25-2003"));
}

///
//unittest
//{
//    immutable brazilTime = new SimpleTimeZone(dur!"seconds"(-10_800));
//    const(TimeZone)[string] timezones = ["BRST" : brazilTime];

//    immutable parsed = parse("Thu Sep 25 10:36:28 BRST 2003", No.ignoreTimezone, timezones);
//    // SysTime opEquals ignores timezones
//    assert(parsed == SysTime(DateTime(2003, 9, 25, 10, 36, 28)));
//    assert(parsed.timezone == brazilTime);

//    assert(parse(
//        "2003 10:36:28 BRST 25 Sep Thu",
//        No.ignoreTimezone,
//        timezones
//    ) == SysTime(DateTime(2003, 9, 25, 10, 36, 28)));
//    assert(parse("Thu Sep 25 10:36:28") == SysTime(DateTime(1, 9, 25, 10, 36, 28)));
//    assert(parse("20030925T104941") == SysTime(DateTime(2003, 9, 25, 10, 49, 41)));
//    assert(parse("2003-09-25T10:49:41") == SysTime(DateTime(2003, 9, 25, 10, 49, 41)));
//    assert(parse("10:36:28") == SysTime(DateTime(1, 1, 1, 10, 36, 28)));
//    assert(parse("09-25-2003") == SysTime(DateTime(2003, 9, 25)));
//}

///// Apply information on top of `defaultDate`
//unittest
//{
//    assert("10:36:28".parse(No.ignoreTimezone, null, No.dayFirst, No.yearFirst,
//        No.fuzzy, SysTime(DateTime(2016, 3, 15)))
//    == SysTime(DateTime(2016, 3, 15, 10, 36, 28)));
//    assert("August 07".parse(No.ignoreTimezone, null, No.dayFirst, No.yearFirst,
//        No.fuzzy, SysTime(DateTime(2016, 1, 1)))
//    == SysTime(Date(2016, 8, 7)));
//    assert("2000".parse(No.ignoreTimezone, null, No.dayFirst, No.yearFirst,
//        No.fuzzy, SysTime(DateTime(2016, 3, 1)))
//    == SysTime(Date(2000, 3, 1)));
//}

///// Custom allocators
//unittest
//{
//    import std.experimental.allocator.mallocator : Mallocator;

//    auto customParser = new Parser!Mallocator(new ParserInfo());
//    assert(customParser.parse("2003-09-25T10:49:41") ==
//        SysTime(DateTime(2003, 9, 25, 10, 49, 41)));
//}

///// Exceptions
//unittest
//{
//    import std.exception : assertThrown;
//    import std.conv : ConvException;

//    assertThrown!ConvException(parse(""));
//    assertThrown!ConvException(parse("AM"));
//    assertThrown!ConvException(parse("The quick brown fox jumps over the lazy dog"));
//    assertThrown!TimeException(parse("Feb 30, 2007"));
//    assertThrown!TimeException(parse("Jan 20, 2015 PM"));
//    assertThrown!ConvException(parse("01-Jane-01"));
//    assertThrown!ConvException(parse("13:44 AM"));
//    assertThrown!ConvException(parse("January 25, 1921 23:13 PM"));
//}
//// dfmt on

//unittest
//{
//    assert(parse("Thu Sep 10:36:28") == SysTime(DateTime(1, 9, 5, 10, 36, 28)));
//    assert(parse("Thu 10:36:28") == SysTime(DateTime(1, 1, 3, 10, 36, 28)));
//    assert(parse("Sep 10:36:28") == SysTime(DateTime(1, 9, 1, 10, 36, 28)));
//    assert(parse("Sep 2003") == SysTime(DateTime(2003, 9, 1)));
//    assert(parse("Sep") == SysTime(DateTime(1, 9, 1)));
//    assert(parse("2003") == SysTime(DateTime(2003, 1, 1)));
//    assert(parse("10:36") == SysTime(DateTime(1, 1, 1, 10, 36)));
//}

//unittest
//{
//    assert(parse("Thu 10:36:28") == SysTime(DateTime(1, 1, 3, 10, 36, 28)));
//    assert(parse("20030925T104941") == SysTime(DateTime(2003, 9, 25, 10, 49, 41)));
//    assert(parse("20030925T1049") == SysTime(DateTime(2003, 9, 25, 10, 49, 0)));
//    assert(parse("20030925T10") == SysTime(DateTime(2003, 9, 25, 10)));
//    assert(parse("20030925") == SysTime(DateTime(2003, 9, 25)));
//    assert(parse("2003-09-25 10:49:41,502") == SysTime(DateTime(2003, 9, 25, 10,
//        49, 41), msecs(502)));
//    assert(parse("199709020908") == SysTime(DateTime(1997, 9, 2, 9, 8)));
//    assert(parse("19970902090807") == SysTime(DateTime(1997, 9, 2, 9, 8, 7)));
//}

//unittest
//{
//    assert(parse("2003 09 25") == SysTime(DateTime(2003, 9, 25)));
//    assert(parse("2003 Sep 25") == SysTime(DateTime(2003, 9, 25)));
//    assert(parse("25 Sep 2003") == SysTime(DateTime(2003, 9, 25)));
//    assert(parse("25 Sep 2003") == SysTime(DateTime(2003, 9, 25)));
//    assert(parse("Sep 25 2003") == SysTime(DateTime(2003, 9, 25)));
//    assert(parse("09 25 2003") == SysTime(DateTime(2003, 9, 25)));
//    assert(parse("25 09 2003") == SysTime(DateTime(2003, 9, 25)));
//    assert(parse("10 09 2003", No.ignoreTimezone, null,
//        Yes.dayFirst) == SysTime(DateTime(2003, 9, 10)));
//    assert(parse("10 09 2003") == SysTime(DateTime(2003, 10, 9)));
//    assert(parse("10 09 03") == SysTime(DateTime(2003, 10, 9)));
//    assert(parse("10 09 03", No.ignoreTimezone, null, No.dayFirst,
//        Yes.yearFirst) == SysTime(DateTime(2010, 9, 3)));
//    assert(parse("25 09 03") == SysTime(DateTime(2003, 9, 25)));
//}

//unittest
//{
//    assert(parse("03 25 Sep") == SysTime(DateTime(2003, 9, 25)));
//    assert(parse("2003 25 Sep") == SysTime(DateTime(2003, 9, 25)));
//    assert(parse("25 03 Sep") == SysTime(DateTime(2025, 9, 3)));
//    assert(parse("Thu Sep 25 2003") == SysTime(DateTime(2003, 9, 25)));
//    assert(parse("Sep 25 2003") == SysTime(DateTime(2003, 9, 25)));
//}

//// Naked times
//unittest
//{
//    assert(parse("10h36m28.5s") == SysTime(DateTime(1, 1, 1, 10, 36, 28), msecs(500)));
//    assert(parse("10h36m28s") == SysTime(DateTime(1, 1, 1, 10, 36, 28)));
//    assert(parse("10h36m") == SysTime(DateTime(1, 1, 1, 10, 36)));
//    assert(parse("10h") == SysTime(DateTime(1, 1, 1, 10, 0, 0)));
//    assert(parse("10 h 36") == SysTime(DateTime(1, 1, 1, 10, 36, 0)));
//    assert(parse("10 hours 36 minutes") == SysTime(DateTime(1, 1, 1, 10, 36, 0)));
//}

//// AM vs PM
//unittest
//{
//    assert(parse("10h am") == SysTime(DateTime(1, 1, 1, 10)));
//    assert(parse("10h pm") == SysTime(DateTime(1, 1, 1, 22)));
//    assert(parse("10am") == SysTime(DateTime(1, 1, 1, 10)));
//    assert(parse("10pm") == SysTime(DateTime(1, 1, 1, 22)));
//    assert(parse("12 am") == SysTime(DateTime(1, 1, 1, 0, 0)));
//    assert(parse("12am") == SysTime(DateTime(1, 1, 1, 0, 0)));
//    assert(parse("11 pm") == SysTime(DateTime(1, 1, 1, 23, 0)));
//    assert(parse("10:00 am") == SysTime(DateTime(1, 1, 1, 10)));
//    assert(parse("10:00 pm") == SysTime(DateTime(1, 1, 1, 22)));
//    assert(parse("10:00am") == SysTime(DateTime(1, 1, 1, 10)));
//    assert(parse("10:00pm") == SysTime(DateTime(1, 1, 1, 22)));
//    assert(parse("10:00a.m") == SysTime(DateTime(1, 1, 1, 10)));
//    assert(parse("10:00p.m") == SysTime(DateTime(1, 1, 1, 22)));
//    assert(parse("10:00a.m.") == SysTime(DateTime(1, 1, 1, 10)));
//    assert(parse("10:00p.m.") == SysTime(DateTime(1, 1, 1, 22)));
//}

//// ISO and ISO stripped
//unittest
//{
//    immutable zone = new SimpleTimeZone(dur!"seconds"(-10_800));

//    immutable parsed = parse("2003-09-25T10:49:41.5-03:00");
//    assert(parsed == SysTime(DateTime(2003, 9, 25, 10, 49, 41), msecs(500), zone));
//    assert((cast(immutable(SimpleTimeZone)) parsed.timezone).utcOffset == hours(-3));

//    immutable parsed2 = parse("2003-09-25T10:49:41-03:00");
//    assert(parsed2 == SysTime(DateTime(2003, 9, 25, 10, 49, 41), zone));
//    assert((cast(immutable(SimpleTimeZone)) parsed2.timezone).utcOffset == hours(-3));

//    assert(parse("2003-09-25T10:49:41") == SysTime(DateTime(2003, 9, 25, 10, 49, 41)));
//    assert(parse("2003-09-25T10:49") == SysTime(DateTime(2003, 9, 25, 10, 49)));
//    assert(parse("2003-09-25T10") == SysTime(DateTime(2003, 9, 25, 10)));
//    assert(parse("2003-09-25") == SysTime(DateTime(2003, 9, 25)));

//    immutable parsed3 = parse("2003-09-25T10:49:41-03:00");
//    assert(parsed3 == SysTime(DateTime(2003, 9, 25, 10, 49, 41), zone));
//    assert((cast(immutable(SimpleTimeZone)) parsed3.timezone).utcOffset == hours(-3));

//    immutable parsed4 = parse("20030925T104941-0300");
//    assert(parsed4 == SysTime(DateTime(2003, 9, 25, 10, 49, 41), zone));
//    assert((cast(immutable(SimpleTimeZone)) parsed4.timezone).utcOffset == hours(-3));

//    assert(parse("20030925T104941") == SysTime(DateTime(2003, 9, 25, 10, 49, 41)));
//    assert(parse("20030925T1049") == SysTime(DateTime(2003, 9, 25, 10, 49, 0)));
//    assert(parse("20030925T10") == SysTime(DateTime(2003, 9, 25, 10)));
//    assert(parse("20030925") == SysTime(DateTime(2003, 9, 25)));
//}

//// Dashes
//unittest
//{
//    assert(parse("2003-09-25") == SysTime(DateTime(2003, 9, 25)));
//    assert(parse("2003-Sep-25") == SysTime(DateTime(2003, 9, 25)));
//    assert(parse("25-Sep-2003") == SysTime(DateTime(2003, 9, 25)));
//    assert(parse("25-Sep-2003") == SysTime(DateTime(2003, 9, 25)));
//    assert(parse("Sep-25-2003") == SysTime(DateTime(2003, 9, 25)));
//    assert(parse("09-25-2003") == SysTime(DateTime(2003, 9, 25)));
//    assert(parse("25-09-2003") == SysTime(DateTime(2003, 9, 25)));
//    assert(parse("10-09-2003", No.ignoreTimezone, null,
//        Yes.dayFirst) == SysTime(DateTime(2003, 9, 10)));
//    assert(parse("10-09-2003") == SysTime(DateTime(2003, 10, 9)));
//    assert(parse("10-09-03") == SysTime(DateTime(2003, 10, 9)));
//    assert(parse("10-09-03", No.ignoreTimezone, null, No.dayFirst,
//        Yes.yearFirst) == SysTime(DateTime(2010, 9, 3)));
//    assert(parse("01-99") == SysTime(DateTime(1999, 1, 1)));
//    assert(parse("99-01") == SysTime(DateTime(1999, 1, 1)));
//    assert(parse("13-01", No.ignoreTimezone, null, Yes.dayFirst) == SysTime(DateTime(1,
//        1, 13)));
//    assert(parse("01-13") == SysTime(DateTime(1, 1, 13)));
//    assert(parse("01-99-Jan") == SysTime(DateTime(1999, 1, 1)));
//}

//// Dots
//unittest
//{
//    assert(parse("2003.09.25") == SysTime(DateTime(2003, 9, 25)));
//    assert(parse("2003.Sep.25") == SysTime(DateTime(2003, 9, 25)));
//    assert(parse("25.Sep.2003") == SysTime(DateTime(2003, 9, 25)));
//    assert(parse("25.Sep.2003") == SysTime(DateTime(2003, 9, 25)));
//    assert(parse("Sep.25.2003") == SysTime(DateTime(2003, 9, 25)));
//    assert(parse("09.25.2003") == SysTime(DateTime(2003, 9, 25)));
//    assert(parse("25.09.2003") == SysTime(DateTime(2003, 9, 25)));
//    assert(parse("10.09.2003", No.ignoreTimezone, null,
//        Yes.dayFirst) == SysTime(DateTime(2003, 9, 10)));
//    assert(parse("10.09.2003") == SysTime(DateTime(2003, 10, 9)));
//    assert(parse("10.09.03") == SysTime(DateTime(2003, 10, 9)));
//    assert(parse("10.09.03", No.ignoreTimezone, null, No.dayFirst,
//        Yes.yearFirst) == SysTime(DateTime(2010, 9, 3)));
//}

//// Slashes
//unittest
//{
//    assert(parse("2003/09/25") == SysTime(DateTime(2003, 9, 25)));
//    assert(parse("2003/Sep/25") == SysTime(DateTime(2003, 9, 25)));
//    assert(parse("25/Sep/2003") == SysTime(DateTime(2003, 9, 25)));
//    assert(parse("25/Sep/2003") == SysTime(DateTime(2003, 9, 25)));
//    assert(parse("Sep/25/2003") == SysTime(DateTime(2003, 9, 25)));
//    assert(parse("09/25/2003") == SysTime(DateTime(2003, 9, 25)));
//    assert(parse("25/09/2003") == SysTime(DateTime(2003, 9, 25)));
//    assert(parse("10/09/2003", No.ignoreTimezone, null,
//        Yes.dayFirst) == SysTime(DateTime(2003, 9, 10)));
//    assert(parse("10/09/2003") == SysTime(DateTime(2003, 10, 9)));
//    assert(parse("10/09/03") == SysTime(DateTime(2003, 10, 9)));
//    assert(parse("10/09/03", No.ignoreTimezone, null, No.dayFirst,
//        Yes.yearFirst) == SysTime(DateTime(2010, 9, 3)));
//}

//// Random formats
//unittest
//{
//    assert(parse("Wed, July 10, '96") == SysTime(DateTime(1996, 7, 10, 0, 0)));
//    assert(parse("1996.07.10 AD at 15:08:56 PDT",
//        Yes.ignoreTimezone) == SysTime(DateTime(1996, 7, 10, 15, 8, 56)));
//    assert(parse("1996.July.10 AD 12:08 PM") == SysTime(DateTime(1996, 7, 10, 12, 8)));
//    assert(parse("Tuesday, April 12, 1952 AD 3:30:42pm PST",
//        Yes.ignoreTimezone) == SysTime(DateTime(1952, 4, 12, 15, 30, 42)));
//    assert(parse("November 5, 1994, 8:15:30 am EST",
//        Yes.ignoreTimezone) == SysTime(DateTime(1994, 11, 5, 8, 15, 30)));
//    assert(parse("1994-11-05T08:15:30-05:00",
//        Yes.ignoreTimezone) == SysTime(DateTime(1994, 11, 5, 8, 15, 30)));
//    assert(parse("1994-11-05T08:15:30Z",
//        Yes.ignoreTimezone) == SysTime(DateTime(1994, 11, 5, 8, 15, 30)));
//    assert(parse("July 4, 1976") == SysTime(DateTime(1976, 7, 4)));
//    assert(parse("7 4 1976") == SysTime(DateTime(1976, 7, 4)));
//    assert(parse("4 jul 1976") == SysTime(DateTime(1976, 7, 4)));
//    assert(parse("7-4-76") == SysTime(DateTime(1976, 7, 4)));
//    assert(parse("19760704") == SysTime(DateTime(1976, 7, 4)));
//    assert(parse("0:01:02") == SysTime(DateTime(1, 1, 1, 0, 1, 2)));
//    assert(parse("12h 01m02s am") == SysTime(DateTime(1, 1, 1, 0, 1, 2)));
//    assert(parse("0:01:02 on July 4, 1976") == SysTime(DateTime(1976, 7, 4, 0, 1, 2)));
//    assert(parse("0:01:02 on July 4, 1976") == SysTime(DateTime(1976, 7, 4, 0, 1, 2)));
//    assert(parse("1976-07-04T00:01:02Z",
//        Yes.ignoreTimezone) == SysTime(DateTime(1976, 7, 4, 0, 1, 2)));
//    assert(parse("July 4, 1976 12:01:02 am") == SysTime(DateTime(1976, 7, 4, 0, 1,
//        2)));
//    assert(parse("Mon Jan  2 04:24:27 1995") == SysTime(DateTime(1995, 1, 2, 4, 24,
//        27)));
//    assert(parse("Tue Apr 4 00:22:12 PDT 1995",
//        Yes.ignoreTimezone) == SysTime(DateTime(1995, 4, 4, 0, 22, 12)));
//    assert(parse("04.04.95 00:22") == SysTime(DateTime(1995, 4, 4, 0, 22)));
//    assert(parse("Jan 1 1999 11:23:34.578") == SysTime(DateTime(1999, 1, 1, 11, 23,
//        34), msecs(578)));
//    assert(parse("950404 122212") == SysTime(DateTime(1995, 4, 4, 12, 22, 12)));
//    assert(parse("0:00 PM, PST", Yes.ignoreTimezone) == SysTime(DateTime(1, 1, 1, 12,
//        0)));
//    assert(parse("12:08 PM") == SysTime(DateTime(1, 1, 1, 12, 8)));
//    assert(parse("5:50 A.M. on June 13, 1990") == SysTime(DateTime(1990, 6, 13, 5,
//        50)));
//    assert(parse("3rd of May 2001") == SysTime(DateTime(2001, 5, 3)));
//    assert(parse("5th of March 2001") == SysTime(DateTime(2001, 3, 5)));
//    assert(parse("1st of May 2003") == SysTime(DateTime(2003, 5, 1)));
//    assert(parse("01h02m03") == SysTime(DateTime(1, 1, 1, 1, 2, 3)));
//    assert(parse("01h02") == SysTime(DateTime(1, 1, 1, 1, 2)));
//    assert(parse("01h02s") == SysTime(DateTime(1, 1, 1, 1, 0, 2)));
//    assert(parse("01m02") == SysTime(DateTime(1, 1, 1, 0, 1, 2)));
//    assert(parse("01m02h") == SysTime(DateTime(1, 1, 1, 2, 1)));
//    assert(parse("2004 10 Apr 11h30m") == SysTime(DateTime(2004, 4, 10, 11, 30)));
//}

//// Pertain, weekday, and month
//unittest
//{
//    assert(parse("Sep 03") == SysTime(DateTime(1, 9, 3)));
//    assert(parse("Sep of 03") == SysTime(DateTime(2003, 9, 1)));
//    assert(parse("Wed") == SysTime(DateTime(1, 1, 2)));
//    assert(parse("Wednesday") == SysTime(DateTime(1, 1, 2)));
//    assert(parse("October") == SysTime(DateTime(1, 10, 1)));
//    assert(parse("31-Dec-00") == SysTime(DateTime(2000, 12, 31)));
//}

//// Fuzzy
//unittest
//{
//    // Sometimes fuzzy parsing results in AM/PM flag being set without
//    // hours - if it's fuzzy it should ignore that.
//    auto s1 = "I have a meeting on March 1 1974.";
//    auto s2 = "On June 8th, 2020, I am going to be the first man on Mars";

//    // Also don't want any erroneous AM or PMs changing the parsed time
//    auto s3 = "Meet me at the AM/PM on Sunset at 3:00 AM on December 3rd, 2003";
//    auto s4 = "Meet me at 3:00AM on December 3rd, 2003 at the AM/PM on Sunset";
//    auto s5 = "Today is 25 of September of 2003, exactly at 10:49:41 with timezone -03:00.";
//    auto s6 = "Jan 29, 1945 14:45 AM I going to see you there?";

//    assert(parse(s1, No.ignoreTimezone, null, No.dayFirst, No.yearFirst,
//        Yes.fuzzy) == SysTime(DateTime(1974, 3, 1)));
//    assert(parse(s2, No.ignoreTimezone, null, No.dayFirst, No.yearFirst,
//        Yes.fuzzy) == SysTime(DateTime(2020, 6, 8)));
//    assert(parse(s3, No.ignoreTimezone, null, No.dayFirst, No.yearFirst,
//        Yes.fuzzy) == SysTime(DateTime(2003, 12, 3, 3)));
//    assert(parse(s4, No.ignoreTimezone, null, No.dayFirst, No.yearFirst,
//        Yes.fuzzy) == SysTime(DateTime(2003, 12, 3, 3)));

//    immutable zone = new SimpleTimeZone(dur!"hours"(-3));
//    immutable parsed = parse(s5, No.ignoreTimezone, null, No.dayFirst, No.yearFirst,
//        Yes.fuzzy);
//    assert(parsed == SysTime(DateTime(2003, 9, 25, 10, 49, 41), zone));

//    assert(parse(s6, No.ignoreTimezone, null, No.dayFirst, No.yearFirst,
//        Yes.fuzzy) == SysTime(DateTime(1945, 1, 29, 14, 45)));
//}

//// dfmt off
///// Custom parser info allows for international time representation
//unittest
//{
//    import std.utf : byChar;

//    class RusParserInfo : ParserInfo
//    {
//        this()
//        {
//            monthsAA = ParserInfo.convert([
//                ["янв", "Январь"],
//                ["фев", "Февраль"],
//                ["мар", "Март"],
//                ["апр", "Апрель"],
//                ["май", "Май"],
//                ["июн", "Июнь"],
//                ["июл", "Июль"],
//                ["авг", "Август"],
//                ["сен", "Сентябрь"],
//                ["окт", "Октябрь"],
//                ["ноя", "Ноябрь"],
//                ["дек", "Декабрь"]
//            ]);
//        }
//    }

//    auto rusParser = new Parser!GCAllocator(new RusParserInfo());
//    immutable parsedTime = rusParser.parse("10 Сентябрь 2015 10:20");
//    assert(parsedTime == SysTime(DateTime(2015, 9, 10, 10, 20)));

//    immutable parsedTime2 = rusParser.parse("10 Сентябрь 2015 10:20"d.byChar);
//    assert(parsedTime2 == SysTime(DateTime(2015, 9, 10, 10, 20)));
//}
//// dfmt on

//// Test ranges
//unittest
//{
//    import std.utf : byCodeUnit, byChar;

//    // forward ranges
//    assert("10h36m28s".byChar.parse == SysTime(
//        DateTime(1, 1, 1, 10, 36, 28)));
//    assert("Thu Sep 10:36:28".byChar.parse == SysTime(
//        DateTime(1, 9, 5, 10, 36, 28)));

//    // bidirectional ranges
//    assert("2003-09-25T10:49:41".byCodeUnit.parse == SysTime(
//        DateTime(2003, 9, 25, 10, 49, 41)));
//    assert("Thu Sep 10:36:28".byCodeUnit.parse == SysTime(
//        DateTime(1, 9, 5, 10, 36, 28)));
//}

//// Test different string types
//unittest
//{
//    import std.meta : AliasSeq;
//    import std.conv : to;

//    alias StringTypes = AliasSeq!(
//        char[], string,
//        wchar[], wstring,
//        dchar[], dstring
//    );

//    foreach (T; StringTypes)
//    {
//        assert("10h36m28s".to!T.parse == SysTime(
//            DateTime(1, 1, 1, 10, 36, 28)));
//        assert("Thu Sep 10:36:28".to!T.parse == SysTime(
//            DateTime(1, 9, 5, 10, 36, 28)));
//        assert("2003-09-25T10:49:41".to!T.parse == SysTime(
//            DateTime(2003, 9, 25, 10, 49, 41)));
//        assert("Thu Sep 10:36:28".to!T.parse == SysTime(
//            DateTime(1, 9, 5, 10, 36, 28)));
//    }
//}

//// Issue #1
//unittest
//{
//    assert(parse("Sat, 12 Mar 2016 01:30:59 -0900",
//        Yes.ignoreTimezone) == SysTime(DateTime(2016, 3, 12, 01, 30, 59)));
//}
