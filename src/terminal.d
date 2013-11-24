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
import std.process;
import std.conv;
import std.exception;
import std.algorithm;
import std.array;
import std.c.stdlib;
import core.thread;
import core.sys.posix.unistd;

import gtk.Widget;
import gtk.DragAndDrop;
import gtk.ScrolledWindow;
import gtk.ScrollableIF;
import gtk.ScrollableT;
import gtk.SelectionData;
import gobject.Signals;
import gdk.Threads;
import gdk.Color;
import gdk.Event;
import gdk.DragContext;
import glib.Regex;
import glib.Source;

import utils.ref_util;
import utils.string_util;
import utils.unistd_util;
import utils.thread_util;
import constants;
import rcfile = config.rcfile;
import config.keybind;
import shellrc = config.shellrc;
import term.search_dialog;
import term.termios;
import thread_list;
import mediator;
import ssh_connection;
import move_files_job;


// wrapper class of VteTerminal widget
class Terminal : Widget, ScrollableIF
{
  override void* getStruct(){return vte_;}
  mixin ScrollableT!(VteTerminal);

  //////////////////// GUI stuff
private:
  VteTerminal * vte_;
  immutable int pty_;
  immutable pid_t pid_;

public:
  this(Mediator mediator,
       string initialDir,
       string terminalRunCommand,
       string delegate(Side, uint) getCWDLR)
  {
    mediator_.init(mediator);
    cwd_      = initialDir;
    getCWDLR_ = getCWDLR;

    vte_ = cast(VteTerminal*)vte_terminal_new();
    super(cast(GtkWidget*)vte_);
    addOnKeyPress(&KeyPressed);

    vte_terminal_set_scrollback_lines(vte_, -1);// infinite scrollback
    vte_terminal_set_audible_bell(vte_, 0);
    vte_terminal_set_background_transparent(vte_, 1);

    // Fork the child process.
    const(char)*[2] argv = [environment["SHELL"].toStringz, null];
    pid_t pid;
    GError *e;
    auto success = vte_terminal_fork_command_full(vte_, cast(VtePtyFlags)0,
                                                  initialDir.toStringz, argv.ptr, null,
                                                  cast(GSpawnFlags)0, null, null, &pid, &e);
    enforce(success, text("!!! [Seta] Failed to fork shell process : ", to!string(e.message)));
    pid_ = pid;
    pty_ = vte_pty_get_fd(vte_terminal_get_pty_object(vte_));

    Signals.connectData(vte_, "child-exited",
                        cast(GCallback)(&CloseThisPageCallback),
                        cast(void*)this, null, GConnectFlags.AFTER);

    InitTermios(pty_);
    InitDragAndDropFunctionality();
    InitSyncFilerDirFunctionality();

    shellSetting_ = shellrc.GetLocalShellSetting();
    ApplyPreferences();

    if(terminalRunCommand.length > 0)
      FeedChild(terminalRunCommand ~ '\n');
  }

  void ApplyPreferences()
  {
    // appearance
    auto colorFore = new Color;
    auto colorBack = new Color;
    Color.parse(rcfile.GetColorForeground(), colorFore);
    Color.parse(rcfile.GetColorBackground(), colorBack);
    vte_terminal_set_colors(vte_, colorFore.getColorStruct(), colorBack.getColorStruct(), null, 0);

    vte_terminal_set_font_from_string(vte_, rcfile.GetFont().toStringz);
    vte_terminal_set_background_saturation(vte_, rcfile.GetTransparency());
    vte_terminal_search_set_wrap_around(vte_, 1);

    // to extract last command and replace $L(R)DIR
    prompt_  = rcfile.GetPROMPT();
    rprompt_ = rcfile.GetRPROMPT();
    enableReplace_ = rcfile.GetEnablePathExpansion();
    ResetReplaceTargets(rcfile.GetReplaceTargetLeft(), rcfile.GetReplaceTargetRight());
  }

private:
  extern(C) static void CloseThisPageCallback(VteTerminal * vte, void * ptr)
  {
    // glib's callback does not grab GDK lock automatically
    threadsEnter();
    auto t = cast(Terminal)ptr;
    t.CancelSyncFilerDirCallback();
    t.mediator_.CloseThisPage();
    threadsLeave();
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
      FeedChild(EscapeSpecialChars(inputPath));
      return true;

    case TerminalAction.InputPWDRight:
      string inputPath = getCWDLR_(Side.RIGHT, 0);// cwd for currently displayed page in right pane
      FeedChild(EscapeSpecialChars(inputPath));
      return true;

    case TerminalAction.Copy:
      vte_terminal_copy_clipboard(vte_);
      return true;

    case TerminalAction.Paste:
      vte_terminal_paste_clipboard(vte_);
      return true;

    case TerminalAction.PasteFilePaths:
      string[] files;
      GetFilesInClipboard(files);
      if(files.length > 0){
        string s = " ";
        foreach(file; files){
          s ~= EscapeSpecialChars(file) ~ ' ';
        }
        FeedChild(s);
      }
      return true;

    case TerminalAction.FindRegexp:
      StartTerminalSearch(this);
      return true;

    case TerminalAction.SyncFilerPWD:
      SyncFilerDirectoryByCwd();
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
        FeedChild(replaced);
      }
      return true;

    default:
      return false;// pass control to the child process
    }
  }
  //////////////////// key pressed



  ////////////////// search
public:
  void SetSearchRegexp(Regex re)
  {
    vte_terminal_search_set_gregex(vte_, re.getRegexStruct());
  }

  void SearchNext()
  {
    vte_terminal_search_find_next(vte_);
  }

  void SearchPrevious()
  {
    vte_terminal_search_find_previous(vte_);
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
    if(ReadyToFeed(pty_, mediator_.FileSystemIsRemote())){
      ClearInputtedCommand();
      string commandString = "cd " ~ EscapeSpecialChars(dirpath) ~ '\n';
      FeedChild(commandString);
    }
  }

  void ChangeDirectoryOfFilerFromCommandLine(string replacedCommand)
  {
    string command = trim(replacedCommand);

    // aliases
    if(shellSetting_ !is null){
      foreach(cdAlias; shellSetting_.GetChangeDirAliases()){
        if(command == cdAlias.command_){
          string path =
            cdAlias.path_[0] == '/' ? cdAlias.path_ :
            cdAlias.path_[0] == '~' ? ExpandPath(mediator_.FileSystemHome()[0..$-1] ~ cdAlias.path_[1..$], mediator_.FileSystemRoot()) :
                                      ExpandPath(cwd_ ~ cdAlias.path_, mediator_.FileSystemRoot());
          if(path !is null){
            if(mediator_.FilerChangeDirFromTerminal(path)){
              cwd_ = mediator_.FileSystemNativePath(path);
            }
          }
          return;
        }
      }
    }

    if(command.StartsWith("cd")){
      string args = triml(command[2..$]);

      if(args.length == 0){// to $HOME
        string home = mediator_.FileSystemHome();
        if(home !is null){
          mediator_.FilerChangeDirFromTerminal(home);
          cwd_ = mediator_.FileSystemNativePath(home);
        }
      }
      else if(args == "-"){// back to previous directory
        string previous = mediator_.FilerCDToPrevious();
        if(previous.length > 0){
          cwd_ = mediator_.FileSystemNativePath(previous);
        }
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
      destination = mediator_.FileSystemRoot() ~ arg1[1..$];
    }
    else if(arg1[0] == '~'){// path from HOME
      string home = mediator_.FileSystemHome();
      if(home is null){
        return;
      }
      destination = home ~ arg1[1..$];
    }
    else{// path from pwd
      destination = cwd_ ~ arg1;
    }

    string absPath = ExpandPath(destination, mediator_.FileSystemRoot());
    if(absPath !is null){
      if(mediator_.FilerChangeDirFromTerminal(absPath)){// change directory here
        cwd_ = mediator_.FileSystemNativePath(absPath);
      }
    }
  }
  ////////////////// traveling directory tree



  ////////////////// automatic sync of filer
private:
  static immutable int PATH_MAX = 4096;// PATH_MAX in /usr/include/linux/limits.h
  char[] readlinkBuffer_;
  uint syncCallbackID_;

  void InitSyncFilerDirFunctionality()
  {
    readlinkBuffer_.length = PATH_MAX + 1;
    syncCallbackID_ = threadsAddTimeoutSeconds(2, &SyncFilerDirectoryByCwdCallback, cast(void*)this);
  }

  string GetCWDFromProcFS()
  {
    string filename = "/proc/" ~ pid_.to!string ~ "/cwd";
    return ReadLink(filename, readlinkBuffer_);
  }

  void SyncFilerDirectoryByCwd()
  {
    if(mediator_.FileSystemIsRemote)
      return; // cwd of the child process can be obtained only within localhost

    auto dirFromProc = GetCWDFromProcFS();
    auto realPath = RealPath(cwd_, readlinkBuffer_);
    if(dirFromProc.empty || realPath.empty)// cannot happen
      return;
    if(realPath != dirFromProc){
      cwd_ = dirFromProc;
      mediator_.FilerChangeDirFromTerminal(cwd_);
    }
  }

  extern(C) static int SyncFilerDirectoryByCwdCallback(void * ptr)
  {
    auto t = cast(Terminal)ptr;
    t.SyncFilerDirectoryByCwd();
    return 1;// continues to call this function
  }

  void CancelSyncFilerDirCallback()
  {
    Source.remove(syncCallbackID_);
  }
  ////////////////// automatic sync of filer



  /////////////////// manipulate text in vte terminal
private:
  shellrc.ShellSetting shellSetting_;
  string prompt_, rprompt_;

  void FeedChild(string text)
  {
    vte_terminal_feed_child(vte_, text.ptr, text.length);
  }

  string GetText()
  {
    char * text = vte_terminal_get_text(vte_, cast(VteSelectionFunc)null, null, null);
    string ret = text.to!string;
    free(text);
    return ret;
  }

  void ClearInputtedCommand()
  {
    static immutable string backspaces = "\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b";
    FeedChild(backspaces);
  }

  string GetLastCommand()
  {
    string text = trimr(GetText());
    size_t indexCompName = locatePatternPrior(text, prompt_);

    if(indexCompName == text.length)
      return null;

    string diff = text[indexCompName .. $];
    size_t indexPrompt = locatePattern(diff, "$ ");
    if(indexPrompt == diff.length){
      indexPrompt = locatePattern(diff, "# ");
    }
    if(indexPrompt == diff.length){
      indexPrompt = locatePattern(diff, "% ");
    }

    if(indexPrompt != diff.length){// if "$ ", "# " or "% " is found
      size_t posNewline = locate(diff, '\n');
      if(indexPrompt+2 < posNewline){
        string line = diff[indexPrompt+2 .. posNewline];
        if(rprompt_.length > 0){
          // if the last char is "]"
          if(line[$-1] == rprompt_[$-1]){
            // search for " [~"
            size_t rpromptStart = locatePatternPrior(line, " " ~ rprompt_[0] ~ '~', line.length-1);
            // search for " [/"
            if(rpromptStart == line.length){
              rpromptStart = locatePatternPrior(line, " " ~ rprompt_[0] ~ '/', line.length-1);
            }
            // search for " [..."
            if(rpromptStart == line.length){
              rpromptStart = locatePatternPrior(line, " " ~ rprompt_[0] ~ "...", line.length-1);
            }

            if(rpromptStart != line.length){
              line = trimr(line[0 .. rpromptStart]);
            }
          }
        }
        return line;
      }
    }

    return null;
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
    if(mediator_.FileSystemIsRemote() || !enableReplace_){
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
      FeedChild(lineNew);
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



  /////////////////// SSH
private:
  class InputPassThread : Thread, StoppableOperationIF
  {
    mixin ListedOperationT;
    Nonnull!Terminal term_;
    string host_, pass_;
    bool cancelled_;

    this(Terminal term, string host, string pass)
    {
      term_.init(term);
      host_ = host;
      pass_ = pass;
      Register();
      super(&Run);
    }

    void Run()// in a temporary thread other than the main thread
    {
      // try to input password for 10 seconds
      for(int i=0; i<20; ++i){
        if(cancelled_)
          break;

        if(AskingPassword(term_.pty_)){
          string lastLine = splitLines(trim(term_.GetText()))[$-1];

          if(lastLine.EndsWith("id_rsa':")){
            // assumes that the password for rsa authentication is the same as the one for remote login
            term_.FeedChild(pass_ ~ '\n');
          }
          else if(lastLine.EndsWith("assword:")){// (there can be both cases of "password:" and "Password:")
            // password is being asked
            term_.FeedChild(pass_ ~ '\n');
            break;
          }
        }

        SleepMillisecs(500);
      }

      // remove from ThreadList
      threadsEnter();
      Unregister();
      threadsLeave();
    }

    void Stop()
    {
      cancelled_ = true;
      Unregister();
    }

    string GetThreadListLabel(string startTime)
    {
      return "Waiting for password query from " ~ host_ ~ " (" ~ startTime ~ ')';
    }

    string GetStopDialogLabel(string startTime)
    {
      return GetThreadListLabel(startTime) ~ ".\nStop this thread?";
    }

    gdk.Window.Window GetAssociatedWindow(){return null;}
  }


public:
  void StartSSH(SSHConnection con)
  {
    shellSetting_ = con.GetShellSetting();
    string host = con.GetUserDomain();
    string password = con.getPassword();
    prompt_ = con.getPrompt();
    rprompt_ = con.getRPrompt();

    ClearInputtedCommand();
    string sshCommand = "ssh " ~ rcfile.GetSSHOption() ~ " " ~ host ~ '\n';
    FeedChild(sshCommand);

    if(password !is null){
      // in order to flush the vte terminal I need some idle time for main thread,
      // so I create a thread to input password
      (new InputPassThread(this, host, password)).start();
    }
    cwd_ = con.getHomeDir();
  }

  void QuitSSH(string pwd)
  {
    shellSetting_ = shellrc.GetLocalShellSetting();
    prompt_  = rcfile.GetPROMPT();
    rprompt_ = rcfile.GetRPROMPT();
    ClearInputtedCommand();
    FeedChild("exit\n");
    cwd_ = pwd;
  }
  /////////////////// SSH



  /////////////////// drag and drop
  void InitDragAndDropFunctionality()
  {
    // accept "text/uri-list" (info==1) and "text/plain" (info==2)
    GtkTargetEntry[] dragTargets = constants.GetDragTargets() ~ GtkTargetEntry(cast(char*)"text/plain".toStringz, 0, 2);
    DragAndDrop.destSet(
      this,
      GtkDestDefaults.ALL,
      dragTargets,
      GdkDragAction.ACTION_MOVE | GdkDragAction.ACTION_COPY);
    addOnDragDataReceived(&DragDataReceived);
  }

  void DragDataReceived(
    DragContext context, int x, int y,
    SelectionData selection, uint info, uint time, Widget w)
  {
    if(info == 1){// URI list
      string[] paths = GetFilesFromSelection(selection.getSelectionDataStruct());
      if(paths.length > 0){
        string s = " ";
        foreach(path; paths){
          s ~= EscapeSpecialChars(path) ~ ' ';
        }
        FeedChild(s);
      }
    }
    else if(info == 2){// plain text, feed the original text
      char * cstr = selection.dataGetText();
      FeedChild(cstr.to!string);
    }

    auto dnd = new DragAndDrop(context.getDragContextStruct());
    dnd.finish(1, 0, 0);

    grabFocus();
  }
  /////////////////// drag and drop
}




// declarations of C functions in libvte
extern(C){
  struct VteTerminal{};
  GtkWidget * vte_terminal_new();

  // miscellaneous settings
  void vte_terminal_set_colors(VteTerminal *terminal,
                               GdkColor *foreground,
                               GdkColor *background,
                               GdkColor *palette,
                               glong palette_size);
  void vte_terminal_set_font_from_string(VteTerminal *terminal,
                                         const char *name);
  void vte_terminal_set_scrollback_lines(VteTerminal *terminal,
                                         glong lines);
  void vte_terminal_set_audible_bell(VteTerminal *terminal,
                                     gboolean is_audible);

  // IO between child process
  void vte_terminal_feed_child(VteTerminal *terminal,
                               const char *text,
                               glong length);
  alias gboolean function(VteTerminal *terminal,
                          glong column,
                          glong row,
                          gpointer data) VteSelectionFunc;
  char * vte_terminal_get_text(VteTerminal *terminal,
                               VteSelectionFunc is_selected,
                               gpointer data,
                               GArray *attributes);

  // transparent background
  void vte_terminal_set_background_transparent(VteTerminal *terminal,
                                               gboolean transparent);
  void vte_terminal_set_background_saturation(VteTerminal *terminal,
                                              double saturation);

  // copy and paste
  void vte_terminal_copy_clipboard(VteTerminal *terminal);
  void vte_terminal_paste_clipboard(VteTerminal *terminal);

  // search
  void vte_terminal_search_set_gregex(VteTerminal *terminal,
                                      GRegex *regex);
  gboolean vte_terminal_search_find_next(VteTerminal *terminal);
  gboolean vte_terminal_search_find_previous(VteTerminal *terminal);
  void vte_terminal_search_set_wrap_around(VteTerminal *terminal,
                                           gboolean wrap_around);

  // process management
  enum VtePtyFlags;
  enum GSpawnFlags;
  alias int GPid;// the same type as pid_t
  alias extern(C) void function(gpointer user_data) GSpawnChildSetupFunc;
  gboolean vte_terminal_fork_command_full(VteTerminal *terminal,
                                          VtePtyFlags pty_flags,
                                          const(char) *working_directory,
                                          const(char)**argv,
                                          const(char)**envv,
                                          GSpawnFlags spawn_flags,
                                          GSpawnChildSetupFunc child_setup,
                                          gpointer child_setup_data,
                                          GPid *child_pid,
                                          GError **error);
  struct VtePty;
  VtePty * vte_terminal_get_pty_object(VteTerminal *terminal);
  int vte_pty_get_fd(VtePty * pty);
}
