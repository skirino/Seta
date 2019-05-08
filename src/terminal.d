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

module terminal;

import std.string;
import std.regex : regex, replaceFirst, split;
import std.process;
import std.conv;
import std.exception;
import std.algorithm : max, min;
import std.array;
import core.thread;
import core.sys.posix.unistd;
import core.sys.posix.signal;

import gtk.Widget;
import gtk.DragAndDrop;
import gtk.SelectionData;
import gtk.TargetEntry;
import gobject.Signals;
import gdk.Threads;
import gdk.Color;
import gdk.RGBA;
import gdk.Event;
import gdk.DragContext;
import glib.Source;
import pango.PgFontDescription;
import vte.Terminal : VTE = Terminal;
import vte.Regex;
import vte.c.types : VteTerminal;
import vte.c.functions;

import utils.ref_util;
import utils.string_util;
import utils.unistd_util;
import constants;
import rcfile = config.rcfile;
import config.keybind;
import shellrc = config.shellrc;
import term.search_dialog;
import term.termios;
import mediator;


// wrapper class of VteTerminal widget
class Terminal : VTE
{
  override void* getStruct(){return vte_;}

  //////////////////// GUI stuff
private:
  VteTerminal * vte_;
  int pty_;
  pid_t pid_ = -1;
  string command_;

public:
  this(Mediator mediator,
       string initialDir,
       string terminalRunCommand,
       string delegate(Side, uint) getCWDLR)
  {
    mediator_.init(mediator);
    cwd_      = initialDir;
    getCWDLR_ = getCWDLR;
    command_  = terminalRunCommand;

    vte_ = cast(VteTerminal*)vte_terminal_new();
    super(vte_);
    setScrollbackLines(-1); // infinite scrollback
    setAudibleBell(false);
    addOnKeyPress(&KeyPressed);

    spawnAsync(cast(VtePtyFlags)0, initialDir, [environment["SHELL"]], null,
               cast(GSpawnFlags)0, null, null, null, -1, null,
               &SpawnFinishCallback, cast(void*)this);
  }

  void InitAfterSpawn()
  {
    pty_ = getPty().getFd();
    addOnChildExited(&CloseThisPageCallback, GConnectFlags.AFTER);
    InitTermios(pty_);
    InitDragAndDropFunctionality();
    InitSyncFilerDirFunctionality();

    shellSetting_ = shellrc.GetLocalShellSetting();
    ApplyPreferences();

    if(command_.length > 0)
      feedChild(command_ ~ '\n');
  }

  void ApplyPreferences()
  {
    // appearance
    auto colorFore = new RGBA();
    auto colorBack = new RGBA();
    enforce(colorFore.parse(rcfile.GetColorForeground()));
    enforce(colorBack.parse(rcfile.GetColorBackground()));
    colorBack.alpha(1.0 - rcfile.GetTransparency());
    setColors(colorFore, colorBack, []);

    auto fontString = rcfile.GetFont();
    auto splitPosition = fontString.lastIndexOf(' ');
    auto fontType = fontString[0 .. splitPosition];
    auto fontSize = fontString[splitPosition + 1 .. $].to!int;
    setFont(new PgFontDescription(fontType, fontSize));
    searchSetWrapAround(true);

    // to extract last command and replace $L(R)DIR
    prompt_  = rcfile.GetPROMPT();
    rprompt_ = rcfile.GetRPROMPT();
    enableReplace_ = rcfile.GetEnablePathExpansion();
    ResetReplaceTargets(rcfile.GetReplaceTargetLeft(), rcfile.GetReplaceTargetRight());
  }

  void KillChildProcessIfStillAlive()
  {
    if(pid_ >= 0) {
      kill(pid_, SIGKILL);
      pid_ = -1;
    }
  }

private:
  void CloseThisPageCallback(int status, VTE term)
  {
    if(pid_ >= 0) {
      mediator_.CloseThisPage();
      pid_ = -1;
    }
  }

  extern(C) static void SpawnFinishCallback(VteTerminal *terminal,
                                            GPid pid,
                                            GError *error,
                                            void *user_data)
  {
    auto t = cast(Terminal)user_data;
    t.pid_ = pid;
    t.InitAfterSpawn();
  }
  //////////////////// GUI stuff



  //////////////////// key pressed
private:
  /+
   + It seems that the newer versions of VTE library calls parent widget's handlers
   + for (at least) "key-press" and "key-release" events TWICE.
   + Avoid processing the same event twice by remembering "time" field in GdkEventKey.
   +/
  uint lastKeyPressTime_ = 0;

  bool KeyPressed(Event e, Widget w)
  {
    auto ekey = e.key();
    if(lastKeyPressTime_ == ekey.time){
      return false;
    }
    else{
      lastKeyPressTime_ = ekey.time;
    }

    int q = QueryAction!"Terminal"(ekey);
    switch(q){

    case -1:
      return false;

    case TerminalAction.ScrollUp:
      auto adj = getVadjustment();
      auto value = max(adj.getLower(), adj.getValue() - rcfile.GetScrollLinesOnKeyAction());
      adj.setValue(value);
      return true;

    case TerminalAction.ScrollDown:
      auto adj = getVadjustment();
      auto value = min(adj.getUpper() - adj.getPageSize(), adj.getValue() + rcfile.GetScrollLinesOnKeyAction());
      adj.setValue(value);
      return true;

    case TerminalAction.Enter:
      // if necessary send command for change directory
      string replacedCommand = ReplaceLRDIRInCommandLine!(string)();
      ChangeDirectoryOfFilerFromCommandLine(replacedCommand);
      return false;

    case TerminalAction.Replace:
      // If successfully replaced, return true to avoid TAB-completion of path.
      return ReplaceLRDIRInCommandLine!(bool)();

    case TerminalAction.InputPWDLeft:
      string inputPath = getCWDLR_(Side.LEFT, 0);// cwd for currently displayed page in left pane
      feedChild(EscapeSpecialChars(inputPath));
      return true;

    case TerminalAction.InputPWDRight:
      string inputPath = getCWDLR_(Side.RIGHT, 0);// cwd for currently displayed page in right pane
      feedChild(EscapeSpecialChars(inputPath));
      return true;

    case TerminalAction.Copy:
      copyClipboard();
      return true;

    case TerminalAction.Paste:
      pasteClipboard();
      return true;

    case TerminalAction.PasteFilePaths:
      string[] files;
      if(files.length > 0){
        string s = " ";
        foreach(file; files){
          s ~= EscapeSpecialChars(file) ~ ' ';
        }
        feedChild(s);
      }
      return true;

    case TerminalAction.FindRegexp:
      StartTerminalSearch(this);
      return true;

    case TerminalAction.InputUserDefinedText1,
      TerminalAction.InputUserDefinedText2,
      TerminalAction.InputUserDefinedText3,
      TerminalAction.InputUserDefinedText4,
      TerminalAction.InputUserDefinedText5,
      TerminalAction.InputUserDefinedText6,
      TerminalAction.InputUserDefinedText7,
      TerminalAction.InputUserDefinedText8,
      TerminalAction.InputUserDefinedText9:
      int index = q + 1 - TerminalAction.InputUserDefinedText1;// 1 <= index <= 9
      string text = rcfile.GetUserDefinedText(index);
      if(text.length > 0){
        if(enableReplace_){
          text = ReplaceLRDIR(text);
        }
        string replaced = text.substitute("\\n", "\n").idup;
        feedChild(replaced);
      }
      return true;

    default:
      return false;// pass control to the child process
    }
  }
  //////////////////// key pressed



  ////////////////// search
public:
  void SetSearchRegexp(string pattern, bool ignoreCase)
  {
    auto PCRE2_CASELESS  = 0x00000008u;
    auto PCRE2_MULTILINE = 0x00000400u;
    auto compileFlags = ignoreCase ? (PCRE2_MULTILINE | PCRE2_CASELESS) : PCRE2_MULTILINE;
    auto re = Regex.newSearch(pattern, -1, compileFlags);
    searchSetRegex(re, 0);
  }
  ////////////////// search



  ////////////////// traveling directory tree
private:
  string cwd_;
  string delegate(Side, uint) getCWDLR_;
  Nonnull!Mediator mediator_;

public:
  void ChangeDirectoryFromFiler(string dirpath)
  {
    cwd_ = dirpath;
    if(ReadyToFeed(pty_, false)){
      ClearInputtedCommand();
      string commandString = "cd " ~ EscapeSpecialChars(dirpath) ~ '\n';
      feedChild(commandString);
    }
  }

  void ChangeDirectoryOfFilerFromCommandLine(string replacedCommand)
  {
    string command = trim(replacedCommand);

    // aliases
    if(shellSetting_ !is null){
      foreach(cdAlias; shellSetting_.GetChangeDirAliases()){
        if(command == cdAlias.command_){
          return;
        }
      }
    }

    if(command.StartsWith("cd")){
      string args = triml(command[2..$]);

      if(args.length == 0){// to $HOME
      }
      else if(args == "-"){// back to previous directory
        cwd_ = "/";
      }
      else{
        if(command[2] == ' '){// "cd" command is separated with its 1st argument by ' '
          ChangeDirTo1stArg(args);
        }
      }
    }
    else{
      if(shellSetting_ !is null && shellSetting_.GetAutoCd()){// if zsh's auto_cd is used, cd can be omitted
        ChangeDirTo1stArg(command);
      }
    }
  }

  void ChangeDirTo1stArg(string args)
  {
    string temp = Extract1stArg(args);
    if(temp.empty)
      return;

    // note that this cannot replace all environment variables
    // since the child process can have original variables
    // which cannot be shared with the process executing this code
    string arg1 = AppendSlash(ExpandEnvVars(temp));
    string destination;

    // convert arg1 to absolute path
    if(arg1[0] == '/'){// path from ROOT
      destination = arg1;
    }
    else if(arg1[0] == '~'){// path from HOME
      destination = arg1;
    }
    else{// path from pwd
      destination = cwd_ ~ arg1;
    }

    string absPath = ExpandPath(destination, "/");
    if(absPath !is null){
      cwd_ = absPath;
    }
  }
  ////////////////// traveling directory tree



  ////////////////// automatic sync of filer
private:
  static immutable int PATH_MAX = 4096;// PATH_MAX in /usr/include/linux/limits.h
  uint syncCallbackID_;
  char[] readlinkBuffer_;

  void InitSyncFilerDirFunctionality()
  {
    readlinkBuffer_.length = PATH_MAX + 1;
  }

  string GetCWDFromProcFS()
  {
    string filename = "/proc/" ~ pid_.to!string ~ "/cwd";
    return ReadLink(filename, readlinkBuffer_);
  }
  ////////////////// automatic sync of filer



  /////////////////// manipulate text in vte terminal
private:
  shellrc.ShellSetting shellSetting_;
  string prompt_, rprompt_;

  string GetText()
  {
    import core.stdc.stdlib : free;
    // Here we don't use getText() method to avoid handling of text attributes (which we don't need).
    char * text = vte_terminal_get_text(vte_, cast(VteSelectionFunc)null, null, null);
    string ret = text.to!string;
    free(text);
    return ret;
  }

  void ClearInputtedCommand()
  {
    static immutable string backspaces = "\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b";
    feedChild(backspaces);
  }

  string GetLastCommand()
  {
    string t0 = trimr(GetText());
    if(t0.empty)
      return null;
    string t1 = t0.split(regex(prompt_))[$ - 1];
    if(t1.length == t0.length)
      return null;
    string t2 = t1.split(regex(rprompt_))[0];
    return trimr(t2);
  }
  /////////////////// manipulate text in vte terminal



  /////////////////// replace $L(R)DIR
private:
  bool enableReplace_;
  string[10] targetsL_, targetsR_;

  void ResetReplaceTargets(string targetLDIR, string targetRDIR)
  {
    targetsL_[0] = substitute(targetLDIR, "<n>", "").idup;
    for(uint i=1; i<10; ++i){
      targetsL_[i] = substitute(targetLDIR, "<n>", i.to!string).idup;
    }

    targetsR_[0] = substitute(targetRDIR, "<n>", "").idup;
    for(uint i=1; i<10; ++i){
      targetsR_[i] = substitute(targetRDIR, "<n>", i.to!string).idup;
    }
  }

  string ReplaceDIR(Side side)(string line)
  {
    static if(side == Side.LEFT){
      alias targetsL_ targets;
    }
    else{
      alias targetsR_ targets;
    }

    string ret = line;

    // this code may have performance problem
    foreach(int i, target; targets){
      if(containsPattern(line, target)){
        string replace = getCWDLR_(side, i);
        if(replace !is null){
          ret = substitute(ret, target, EscapeSpecialChars(replace)).idup;
        }
      }
    }

    return ret;
  }

  string ReplaceLRDIR(string line)
  {
    return ReplaceDIR!(Side.RIGHT)(ReplaceDIR!(Side.LEFT)(line));
  }

  R ReplaceLRDIRInCommandLine(R)()// R is "bool" or "string"
  {
    string lineOld = GetLastCommand();

    // do nothing when working within remote shell or replacing functionality is disabled
    if(!enableReplace_){
      static if(is(R == bool)){
        return false;
      }
      else{
        return lineOld;
      }
    }

    string lineNew = ReplaceLRDIR(lineOld);

    if(lineOld != lineNew){
      ClearInputtedCommand();
      feedChild(lineNew);
      static if(is(R == bool)){
        return true;
      }
    }

    static if(is(R == bool)){
      return false;
    }
    else{
      static assert(is(R == string));
      return lineNew;
    }
  }
  /////////////////// replace $L(R)DIR



  /////////////////// drag and drop
  void InitDragAndDropFunctionality()
  {
    // accept "text/uri-list" (info==1) and "text/plain" (info==2)
    TargetEntry[] dragTargets = constants.GetDragTargets() ~ constants.GetTextPlainDragTarget();
    dragDestSet(GtkDestDefaults.ALL, dragTargets, GdkDragAction.MOVE | GdkDragAction.COPY);
    addOnDragDataReceived(&DragDataReceived);
  }

  void DragDataReceived(
    DragContext context, int x, int y,
    SelectionData selection, uint info, uint time, Widget w)
  {
    if(info == 1){// URI list
      string[] paths;
      if(paths.length > 0){
        string s = " ";
        foreach(path; paths){
          s ~= EscapeSpecialChars(path) ~ ' ';
        }
        feedChild(s);
      }
    }
    else if(info == 2){// plain text, feed the original text
      feedChild(selection.getText());
    }

    DragAndDrop.dragFinish(context, 1, 0, 0);

    grabFocus();
  }
  /////////////////// drag and drop
}
