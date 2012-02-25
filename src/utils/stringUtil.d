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

module stringUtil;

private import gtk.Label;
private import glib.Str;

private import tango.io.Stdout;
private import tango.sys.Environment;
private import tango.text.Util;
private import tango.io.stream.Lines;
private import tango.util.MinMax;
private import tango.stdc.ctype;
private import tango.stdc.string;


bool IsBlank(string s)
{
  return (s is null) || (s.length == 0);
}

string[] ToStringArray(T)(T[] array)
{
  string[] ret;
  ret.length = array.length;
  foreach(i, e; array)
  {
    ret[i] = e.toString();
  }
  return ret;
}


string[] TrimAll(string[] l)
{
  string[] ret;
  ret.length = l.length;
  foreach(i, e; l){
    ret[i] = trim(e);
  }
  return ret;
}


// fast strcmp for D strings
int StrCmp(string s1, string s2)
{
  auto len = s1.length;
  if (s2.length < len){
    len = s2.length;
  }
  
  int result = memcmp(s1.ptr, s2.ptr, len);
  if (result == 0)
    result = cast(int)s1.length - cast(int)s2.length;
  return result;
}


// width in pixel of a text displayed in a GtkLabel
int GetTextWidth(string text)
{
  static Label l;
  if(l is null){
    l = new Label("");
  }
  int width, height;
  l.setText(text);
  l.getLayout().getPixelSize(width, height);
  return width;
}


string NonnullString(string s)
{
  return s is null ? "" : s;
}


string PluralForm(INT, string singularForm, string pluralForm = singularForm ~ "s")(INT n)
{
  static if(is(INT == int)){
    if(n == -1){
      return "? " ~ pluralForm;
    }
  }
  
  if(n == 1){
    return "1 " ~ singularForm;
  }
  else{
    return Str.toString(n) ~ ' ' ~ pluralForm;
  }
}


bool CompareStr(string s1, string s2)
{
  return Str.strcmp0(s1, s2) < 0;
}


bool StartsWith(string s1, string s2)
{
  if(s1.length >= s2.length){
    return s1[0 .. s2.length] == s2;
  }
  return false;
}


bool EndsWith(string s1, string s2)
{
  if(s1.length >= s2.length){
    return s1[$-s2.length .. $] == s2;
  }
  return false;
}


string LineInFileWhichStartsWith(string phrase, string filename)
{
  string ret;
  try{
    scope file = new tango.io.device.File.File(filename);
    scope lines = new Lines!(char)(file);
    foreach(line; lines){
      if(line.StartsWith(phrase)){
        ret = line[phrase.length+1 .. $];// return remaining part (excludes "phrase")
        break;
      }
    }
    file.close;
  }
  catch(Exception ex){}// cannot open (no such file, permission denied)
  
  return ret;
}


string AppendSlash(string s)
{
  if(s is null){
    return "/";
  }
  else{
    return (s[$-1] == '/') ? s : s ~ '/';
  }
}


string RemoveSlash(string s)
{
  if(s[$-1] == '/'){
    return s[0..$-1];
  }
  else{
    return s;
  }
}


string GetBasename(string path)
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


string ExpandPath(string path, string root)
{
  assert(path[0] == '/');
  assert(path[$-1] == '/');
  
  // first obtain an absolute path from the root directory
  // replace "////..." to "/"
  while(containsPattern(path, "//")){
    path = substitute(path, "//", "/");
  }
  
  // replace "/./" before "/../"
  while(containsPattern(path, "/./")){
    path = substitute(path, "/./", "/");
  }
  
  // if "/path/to/somewhere/../" is found replace with its parent directory
  size_t pos;
  while((pos = path.locatePattern("/../")) != path.length){
    string parent = ParentDirectory(path[0..pos+1], root);
    path = parent ~ path[pos+4..$];
  }
  
  // now "path" becomes an absolute path.
  // next substitute escaped chars into original ones
  path = UnescapeSpecialChars(path);
  
  // "path" should start with "root".
  // if not, "path" is modified as "root" ~ "path"
  if(!path.StartsWith(root)){
    path = root[0 .. $-1] ~ path;// remove '/' at the last of "root"
  }
  
  return path;
}


// backslash should be the first entry
private static string SpecialChars = "\\!\"$&\'()~=|`{}[]*:;<>?, ";

string EscapeSpecialChars(string input)
{
  string ret = input;
  foreach(c; SpecialChars){
    ret = substitute(ret, "" ~ c, "\\" ~ c);
  }
  return ret;
}


string UnescapeSpecialChars(string input)
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
string ParentDirectory(string dir, string root = "/")
{
  if(dir == "/" || dir == root){
    return root;
  }
  else{
    assert(dir.length > 1);
    size_t index = dir.length-2;// dir[$-1] == '/'
    while(dir[index] != '/'){
      --index;
    }
    return dir[0..index+1];// dir[0..index+1] end with '/'
  }
}


string Extract1stArg(string args)
{
  // "args" is already trimmed, so there is no whitespace at both start and end of the input
  string replaced = ReplaceQuotedArg(args);
  if(replaced.length == 0){
    return null;
  }
  else{
    size_t posSpace = FindUnescapedChar(replaced, ' ');
    size_t posNewline = locate(replaced, '\n');
    size_t posSemicolon = FindUnescapedChar(replaced, ';');
    return replaced[0 .. min(min(posSpace, posNewline), posSemicolon)];
  }
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
    if(end == args.length){// unmatched
      return null;
    }
    else{
      ret ~= args[index .. start];
      ret ~= EscapeSpecialChars(args[start + 1 .. end]);
      index = end+1;
      if(index == args.length){
        break;
      }
    }
  }
  
  return ret;
}


private size_t ReverseCountBackslash(string s)
{
  int pos = s.length-1;
  while(pos >= 0 && s[pos] == '\\'){
    --pos;
  }
  return s.length - 1 - pos;
}


private size_t FindUnescapedChar(string s, char target, size_t start = 0)
{
  for(size_t i=start; i<s.length; ++i){
    if(s[i] == target){
      if(i == 0 ||
         ReverseCountBackslash(s[0 .. i-1]) % 2 == 1
        ){
        return i;
      }
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
    if(dollar == arg.length){
      break;
    }
    
    // extract variable token
    size_t end = dollar+1;
    while(end != arg.length && !(iscntrl(arg[end]) || arg[end] == '/')){
      ++end;
    }
    string var = arg[dollar..end];
    
    ret ~= Environment.get(var[1..$], var);
    indexStart = end;
  }
  
  return ret;
}


string RemovePercentBrace(string s)
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
      
      if(open == 0){
        ret ~= '%';
      }
    }
    else{
      if(open == 0){
        ret ~= s[i];
      }
    }
  }
  
  return ret;
}
