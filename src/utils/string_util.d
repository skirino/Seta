/*
Copyright (C) 2012 Shunsuke Kirino <shunsuke.kirino@gmail.com>

This file is part of Seta.
This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 3, or (at your option)
any later version.

This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
General Public License for more details.

You should have received a copy of the GNU General Public License
along with this software; see the file GPL. If not, contact the
Free Software Foundation, 51 Franklin Street, Fifth Floor, Boston,
MA 02110-1301 USA.
*/

module utils.string_util;

import std.string;
import std.stdio;
import std.c.string;
import std.ascii;
import std.process;
import std.algorithm : min, map;
import std.array;
import std.conv;

import gtk.Label;


pure char** ToStringzArray(string[] array)
{
  // This function exists since glib.Str.toStringzArray seems to have an off-by-one error.
  if(array.length == 0)
    return null;
  char** ret = (new char*[array.length + 1]).ptr;
  foreach(size_t i, str; array){
    ret[i] = cast(char*)(str.dup ~ '\0');
  }
  ret[array.length] = null;
  return ret;
}

unittest{
  assert(ToStringzArray([]) == null);
  auto p1 = ToStringzArray(["a"]);
  assert(p1[0].to!string == "a");
  assert(p1[1] == null);
  auto p2 = ToStringzArray(["ho", "ge"]);
  assert(p2[0].to!string == "ho");
  assert(p2[1].to!string == "ge");
  assert(p2[2] == null);
}


// fast strcmp for D strings
pure int StrCmp(string s1, string s2)
{
  int result = memcmp(s1.ptr, s2.ptr, min(s1.length, s2.length));
  if (result == 0)
    result = cast(int)s1.length - cast(int)s2.length;
  return result;
}

unittest{
  assert(StrCmp("abc", "abc") == 0);
  assert(StrCmp("ab" , "abc") < 0);
  assert(StrCmp("abb", "abc") < 0);
  assert(StrCmp("abc", "ab" ) > 0);
  assert(StrCmp("abc", "abb") > 0);
}


// width in pixel of a text displayed in a GtkLabel
int GetTextWidth(string text)
{
  static __gshared Label l;
  if(l is null)
    l = new Label("");

  int width, height;
  l.setText(text);
  l.getLayout().getPixelSize(width, height);
  return width;
}


pure string NonnullString(string s)
{
  return s is null ? "" : s;
}


string PluralForm(INT, string singularForm, string pluralForm = singularForm ~ "s")(INT n)
{
  static if(is(INT == int)){
    if(n == -1)
      return "? " ~ pluralForm;
  }

  if(n == 1)
    return "1 " ~ singularForm;
  else
    return n.to!string ~ ' ' ~ pluralForm;
}


pure bool StartsWith(string s1, string s2)
{
  if(s1.length >= s2.length)
    return s1[0 .. s2.length] == s2;
  return false;
}


pure bool EndsWith(string s1, string s2)
{
  if(s1.length >= s2.length)
    return s1[$-s2.length .. $] == s2;
  return false;
}


void EachLineInFile(string filename, bool delegate(string) f)
{
  try{
    scope file = File(filename);
    foreach(line; file.byLine()){
      bool continueLoop = f(line.idup);
      if(!continueLoop)
        break;
    }
  }
  catch(Exception ex){}// no such file or permission denied
}


string LineInFileWhichStartsWith(string phrase, string filename)
{
  string ret;
  EachLineInFile(filename, delegate bool(string line){
      if(line.StartsWith(phrase)){
        ret = line[phrase.length .. $];// return remaining part
        return false;
      }
      return true;
    });
  return ret;
}


pure string AppendSlash(string s)
{
  if(s is null)
    return "/";
  else
    return (s[$-1] == '/') ? s : s ~ '/';
}


pure string RemoveSlash(string s)
{
  if(s[$-1] == '/')
    return s[0..$-1];
  else
    return s;
}


pure string GetBasename(string path)
{
  if(path == "/"){
    return path;
  }
  else{
    size_t pos = locatePrior(path, '/', path.length-1);
    assert(pos != path.length);
    return path[pos+1..$];
  }
}


pure string ExpandPath(string path, string root)
{
  /+
   + Canonicalize path by expanding "//", "." and "..".
   + "realpath" cannot be used here since symlinks should not be expanded.
   +/
  assert(path[0] == '/');
  assert(path[$-1] == '/');

  char[] ret = path.dup;

  // first obtain an absolute path from the root directory
  // replace "////..." to "/"
  while(containsPattern(ret, "//")){
    ret = substitute(ret, "//", "/");
  }

  // replace "/./" before "/../"
  while(containsPattern(ret, "/./")){
    ret = substitute(ret, "/./", "/");
  }

  // if "/path/to/somewhere/../" is found replace with its parent directory
  size_t pos;
  while((pos = ret.locatePattern("/../")) != ret.length){
    string parent = ParentDirectory(ret[0..pos+1].idup, root);
    ret = parent ~ ret[pos+4..$];
  }

  // now "ret" becomes an absolute path.
  // next substitute escaped chars into original ones
  ret = UnescapeSpecialChars(ret.idup).dup;

  // "ret" should start with "root".
  // if not, "ret" is modified as "root" ~ "ret"
  if(!ret.idup.StartsWith(root)){
    ret = root[0 .. $-1] ~ ret;// remove '/' at the last of "root"
  }

  return ret.idup;
}


// backslash should be the first entry
private immutable string SpecialChars = "\\!\"$&\'()~=|`{}[]*:;<>?, ";

pure string EscapeSpecialChars(string input)
{
  char[] ret = input.dup;
  foreach(c; SpecialChars){
    ret = ret.substitute("" ~ c, "\\" ~ c);
  }
  return ret.idup;
}


pure string UnescapeSpecialChars(string input)
{
  string ret;
  for(int i=0; i<input.length; ++i){
    char c1 = input[i];
    if(c1 == '\\' && i<input.length-1){
      char c2 = input[i+1];
      foreach(c; SpecialChars){
        if(c2 == c){
          ret ~= c;
          ++i;// proceed 2 chars
          goto end_of_loop;
        }
      }

      // no match in SpecialChars
      ret ~= input[i..i+2];
      ++i;// proceed 2 chars
    }
    else{
      ret ~= c1;
    }

    end_of_loop:;
  }

  return ret;
}


// not to go beyond root directory of filesystem
pure string ParentDirectory(string dir, string root = "/")
{
  if(dir == "/" || dir == root)
    return root;

  assert(dir.length > 1);
  size_t index = dir.length-2;// dir[$-1] == '/'
  while(dir[index] != '/'){
    --index;
  }
  return dir[0..index+1];// dir[0..index+1] end with '/'
}


string Extract1stArg(string args)
{
  // "args" is already trimmed, so there is no whitespace at both start and end of the input
  string replaced = ReplaceQuotedArg(args);
  if(replaced.length == 0)
    return null;

  size_t posSpace = FindUnescapedChar(replaced, ' ');
  size_t posNewline = locate(replaced, '\n');
  size_t posSemicolon = FindUnescapedChar(replaced, ';');
  return replaced[0 .. min(min(posSpace, posNewline), posSemicolon)];
}


private string ReplaceQuotedArg(string args)
{
  size_t index = 0;
  string ret;

  while(true){
    size_t startQuote1 = FindUnescapedChar(args, '\'', index);
    size_t startQuote2 = FindUnescapedChar(args, '\"', index);

    if(startQuote1 == args.length && startQuote2 == args.length){
      ret ~= args[index .. $];
      break;
    }

    size_t start;
    char quotation;
    if(startQuote1 < startQuote2){// '\'' comes faster than '\"'
      start = startQuote1;
      quotation = '\'';
    }
    else{// '\"' comes faster than '\''
      start = startQuote2;
      quotation = '\"';
    }

    size_t end = FindUnescapedChar(args, quotation, start+1);
    if(end == args.length)// unmatched
      return null;

    ret ~= args[index .. start];
    ret ~= EscapeSpecialChars(args[start + 1 .. end]);
    index = end+1;
    if(index == args.length)
      break;
  }

  return ret;
}


pure private size_t ReverseCountBackslash(string s)
{
  if(s.length == 0)
    return 0;

  size_t num = 0;
  size_t pos = s.length-1;
  while(pos >= 0 && s[pos] == '\\'){
    ++num;
    --pos;
  }
  return num;
}


pure private size_t FindUnescapedChar(string s, char target, size_t start = 0)
{
  for(size_t i=start; i<s.length; ++i){
    if(s[i] == target){
      if(i == 0 || ReverseCountBackslash(s[0 .. i-1]) % 2 == 0)
        return i;
    }
  }
  return s.length;
}


string ExpandEnvVars(string arg)
{
  size_t indexStart = 0;
  string ret;

  while(indexStart != arg.length){
    // find dollar which is not escaped by backslash
    size_t dollar = FindUnescapedChar(arg, '$', indexStart);
    ret ~= arg[indexStart .. dollar];
    if(dollar == arg.length)
      break;

    // extract variable token
    size_t end = dollar+1;
    while(end != arg.length && !(isControl(arg[end]) || arg[end] == '/')){
      ++end;
    }
    string var = arg[dollar..end];

    ret ~= getenv(var[1..$]) || var;
    indexStart = end;
  }

  return ret;
}


pure string RemovePercentBrace(string s)
{
  int open = 0;
  string ret;

  for(size_t i=0; i<s.length; ++i){
    if(s[i] == '%'){
      if(i<s.length-1){
        if(s[i+1] == '{'){
          ++i;
          ++open;
          continue;
        }
        else if(s[i+1] == '}'){
          ++i;
          --open;
          continue;
        }
      }

      if(open == 0)
        ret ~= '%';
    }
    else{
      if(open == 0)
        ret ~= s[i];
    }
  }

  return ret;
}




// tango compatibility layer
C[] triml(C)(C[] s)
{
  foreach(i, c; s){
    if(!isWhite(c))
      return s[i .. $];
  }
  return "";
}

C[] trimr(C)(C[] s)
{
  for(ptrdiff_t i=s.length-1; i>=0; --i){
    if(!isWhite(s[i]))
      return s[0 .. i+1];
  }
  return "";
}

C[] trim(C)(C[] s)
{
  return s.triml().trimr();
}


unittest
{
  assert("" == triml(""));
  assert("" == trimr(""));
  assert("" == trim(""));

  string x = "abcあいう";
  assert(x == x.triml());
  assert(x == x.trimr());
  assert(x == x.trim());

  string y = "  abcあいう  ";
  assert("abcあいう  " == y.triml());
  assert("  abcあいう" == y.trimr());
  assert("abcあいう"   == y.trim());

  string z = "   ";
  assert("" == z.triml());
  assert("" == z.trimr());
  assert("" == z.trim());
}



C[] substitute(C)(const(C)[] s, const(C)[] from, const(C)[] to)
{
  if(from.length == 0)
    return s.dup;

  C[] p;
  size_t istart = 0;
  while(istart < s.length){
    auto i = indexOf(s[istart .. s.length], from);
    if(i == -1){
      p ~= s[istart .. s.length];
      break;
    }
    p ~= s[istart .. istart + i];
    p ~= to;
    istart += i + from.length;
  }
  return p;
}

unittest
{
  string x = "abcあいうabc123abc";
  assert(x == x.substitute("",   "def"));
  assert(x == x.substitute("nohit", "def"));

  // Should accept both mutable and immutable strings
  assert("defあいうdef123def" == x    .substitute("abc",     "def"));
  assert("defあいうdef123def" == x.dup.substitute("abc",     "def"));
  assert("defあいうdef123def" == x    .substitute("abc".dup, "def"));
  assert("defあいうdef123def" == x.dup.substitute("abc".dup, "def"));
  assert("defあいうdef123def" == x    .substitute("abc".dup, "def".dup));
  assert("defあいうdef123def" == x.dup.substitute("abc".dup, "def".dup));

  // Should substitute multibyte chars
  assert("abcえおabc123abc" == x.substitute("あいう", "えお"));
}



private immutable string LocateFunctionBody =
"
  if(start >= source.length)
    return source.length;

  auto i = source[start .. $].indexOf(match);
  if(i == -1)
    return source.length;
  else
    return i + start;
";

size_t locate(C1, C2)(const(C1)[] source, const(C2) match, size_t start = 0)
{
  mixin(LocateFunctionBody);
}
size_t locatePattern(C)(const(C)[] source, const(C)[] match, size_t start = 0)
{
  mixin(LocateFunctionBody);
}

unittest
{
  string x = "abcあいう123";
  assert(0        == x.locate('a'));
  assert(0        == x.dup.locate('a'));
  assert(6        == x.locate('い')); // 'あ' is 3-byte character in UTF-8
  assert(6        == x.dup.locate('い'));
  assert(x.length == x.locate('x'));
  assert(x.length == x.locate('x', 100));
  assert(x.length == x.locate('a', 1));
  assert(x.length == x.locate('a', 100));
  assert(2        == x.locate('c', 1));

  assert(0        == x.locatePattern("abc"));
  assert(0        == x.dup.locatePattern("abc"));
  assert(3        == x.locatePattern("あいう"));
  assert(1        == x.locatePattern("bcあ"));
  assert(x.length == x.locatePattern("xyz"));
}



private immutable string LocatePriorFunctionBody =
"
  if(start >= source.length)
    start = source.length;

  auto i = source[0 .. start].lastIndexOf(match);
  if(i == -1)
    return source.length;
  else
    return i;
";

size_t locatePrior(C1, C2)(const(C1)[] source, const(C2) match, size_t start = size_t.max)
{
  mixin(LocatePriorFunctionBody);
}
size_t locatePatternPrior(C)(const(C)[] source, const(C)[] match, size_t start = size_t.max)
{
  mixin(LocatePriorFunctionBody);
}

unittest
{
  string x = "abcあいう123";
  assert(x.length == x.locatePrior('x'));
  assert(x.length == x.dup.locatePrior('x'));
  assert(x.length == x.locatePrior('x', 5));
  assert(0        == x.locatePrior('a'));
  assert(0        == x.locatePrior('a', 13));
  assert(6        == x.locatePrior('い'));
  assert(6        == x.locatePrior('い', 13));
  assert(13       == x.locatePrior('2'));
  assert(x.length == x.locatePrior('2', 13));

  assert(0        == x.locatePatternPrior("abc"));
  assert(0        == x.dup.locatePatternPrior("abc"));
  assert(3        == x.locatePatternPrior("あいう"));
  assert(1        == x.locatePatternPrior("bcあ"));
  assert(x.length == x.locatePatternPrior("xyz"));
}



bool contains(C1, C2)(const(C1)[] source, const(C2) match)
{
  return source.locate(match) != source.length;
}
bool containsPattern(C)(const(C)[] source, const(C)[] match)
{
  return source.locatePattern(match) != source.length;
}

unittest
{
  string x = "abcあいう123";
  assert(x.contains('a'));
  assert(x.dup.contains('a'));
  assert(x.contains('あ'));
  assert(!x.contains('x'));

  assert(x.containsPattern("abc"));
  assert(x.dup.containsPattern("abc"));
  assert(!x.containsPattern("xyz"));
}
