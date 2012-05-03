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

import gtk.Widget;
import gtk.Selections;
import gtk.DragAndDrop;
import gobject.Signals;
import gdk.Threads;
import gdk.Color;
import glib.Str;
import glib.Regex;
import glib.Source;

import std.string;
import std.process;
import std.c.stdlib;
import core.thread;
import core.sys.posix.unistd;

import utils.string_util;
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
class Terminal : Widget
{
  //////////////////// GUI stuff
private:
  VteTerminal * vte_;
  int pty_;
  pid_t pid_;

public:
  this(Mediator mediator, string initialDir, string delegate(char, uint) getCWDLR)
  {
    mediator_ = mediator;
    cwd_ = initialDir;
    getCWDLR_ = getCWDLR;

    vte_ = cast(VteTerminal*)vte_terminal_new();
    super(cast(GtkWidget*)vte_);
    addOnKeyPress(&KeyPressed);

    vte_terminal_set_scrollback_lines(vte_, -1);// infinite scrollback
    vte_terminal_set_audible_bell(vte_, 0);

    // transparent background
    vte_terminal_set_background_transparent(vte_, 1);

    // Fork the child process.
    // Passing "argv" is essential when the default shell is zsh.
    char *[2] argv = [Str.toStringz(std.process.getenv("SHELL")), null];
    // deprecated since 0.26
    pid_ = vte_terminal_fork_command(
      vte_, argv[0], argv.ptr, null,
      Str.toStringz(initialDir), 0, 0, 0);
    // since 0.26
    //vte_terminal_fork_command_full(vte_, cast(VtePtyFlags)0, Str.toStringz(initialDir), argv.ptr, null,
    //                               cast(GSpawnFlags)0, null, null, &pid_, null);

    // deprecated since 0.26
    pty_ = vte_terminal_get_pty(vte_);
    // since 0.26
    //VtePty * ptyObj = vte_terminal_get_pty_object(vte_);
    //pty_ = vte_pty_get_fd(ptyObj);

    Signals.connectData(vte_, "child-exited",
                        cast(GCallback)(&CloseThisPageCallback),
                        cast(void*)this, null, GConnectFlags.AFTER);

    InitTermios(pty_);
    InitDragAndDropFunctionality();
    InitSyncFilerDirFunctionality();

    shellSetting_ = shellrc.GetLocalShellSetting();
    ApplyPreferences();
  }

  void ApplyPreferences()
  {
    // appearance
    GdkColor colorFore, colorBack;
    Color.parse(rcfile.GetColorForeground(), colorFore);
    Color.parse(rcfile.GetColorBackground(), colorBack);
    vte_terminal_set_colors(vte_, &colorFore, &colorBack, null, 0);

    vte_terminal_set_font_from_string(vte_, Str.toStringz(rcfile.GetFont()));
    vte_terminal_set_background_saturation(vte_, rcfile.GetTransparency());

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
    gdkThreadsEnter();
    auto t = cast(Terminal)ptr;
    t.CancelSyncFilerDirCallback();
    t.mediator_.CloseThisPage();
    gdkThreadsLeave();
  }
  //////////////////// GUI stuff



  //////////////////// key pressed
private:
  bool KeyPressed(GdkEventKey * ekey, Widget w)
  {
    int q = QueryTerminalAction(ekey);
    switch(q){

    case -1:
      return false;

    case TerminalAction.Enter:
      // if necessary send command for change directory
      string replacedCommand = ReplaceLRDIRInCommandLine!(string)();
      ChangeDirectoryOfFilerFromCommandLine(replacedCommand);
      return false;

    case TerminalAction.Replace:
      // If successfully replaced, return true to avoid TAB-completion of path.
      return ReplaceLRDIRInCommandLine!(bool)();

    case TerminalAction.InputPWDLeft:
      string inputPath = getCWDLR_('L', 0);// cwd for currently displayed page in left pane
      FeedChild(EscapeSpecialChars(inputPath));
      return true;

    case TerminalAction.InputPWDRight:
      string inputPath = getCWDLR_('R', 0);// cwd for currently displayed page in right pane
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

  void SetOverwrappedSearch(int i)
  {
    vte_terminal_search_set_wrap_around(vte_, i);
  }
  ////////////////// search



  ////////////////// traveling directory tree
private:
  string cwd_;
  string delegate(char, uint) getCWDLR_;
  Mediator mediator_;

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
    if(temp is null){
      return;
    }

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
  static const int PATH_MAX = 4096;// PATH_MAX in /usr/include/linux/limits.h
  char[] readlink_buffer_;
  uint syncCallbackID_;

  void InitSyncFilerDirFunctionality()
  {
    readlink_buffer_.length = PATH_MAX + 1;
    syncCallbackID_ = gdkThreadsAddTimeoutSeconds(2, &SyncFilerDirectoryByCwdCallback, cast(void*)this);
  }

  void SyncFilerDirectoryByCwd()
  {
    // adjust directory of file manager
    if(!mediator_.FileSystemIsRemote()){// cwd of the child process can be obtained only within localhost
      string filename = "/proc/" ~ Str.toString(pid_) ~ "/cwd\0";
      ssize_t len = readlink(filename.ptr, readlink_buffer_.ptr, readlink_buffer_.length);
      if(len != -1){
        cwd_ = AppendSlash(readlink_buffer_[0..len].idup);
        mediator_.FilerChangeDirFromTerminal(cwd_);
      }
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
    vte_terminal_feed_child(vte_, cast(char*)text.ptr, text.length);
  }

  string GetText()
  {
    char * text = vte_terminal_get_text(vte_, cast(VteSelectionFunc)null, null, null);
    string ret = Str.toString(text);
    free(text);
    return ret;
  }

  void ClearInputtedCommand()
  {
    static const string backspaces = "\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b";
    FeedChild(backspaces);
  }

  string GetLastCommand()
  {
    string text = trimr(GetText());
    size_t indexCompName = locatePatternPrior(text, prompt_);

    if(indexCompName == text.length){
      return null;
    }

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

            // if not found, search for " [/"
            if(rpromptStart == line.length){
              rpromptStart = locatePatternPrior(line, " " ~ rprompt_[0] ~ '/', line.length-1);
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
      targetsL_[i] = substitute(targetLDIR, "<n>", Str.toString(i)).idup;
    }

    targetsR_[0] = substitute(targetRDIR, "<n>", "").idup;
    for(uint i=1; i<10; ++i){
      targetsR_[i] = substitute(targetRDIR, "<n>", Str.toString(i)).idup;
    }
  }

  string ReplaceDIR(char LR)(string line)
  {
    static if(LR == 'L'){
      alias targetsL_ targets;
    }
    else{
      alias targetsR_ targets;
    }

    string ret = line;

    // this code may have performance problem
    foreach(int i, target; targets){
      if(containsPattern(line, target)){
        string replace = getCWDLR_(LR, i);
        if(replace !is null){
          ret = substitute(ret, target, EscapeSpecialChars(replace)).idup;
        }
      }
    }

    return ret;
  }

  string ReplaceLRDIR(string line)
  {
    return ReplaceDIR!('R')(ReplaceDIR!('L')(line));
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
    Terminal term_;
    string host_, pass_;
    bool cancelled_;

    this(Terminal term, string host, string pass)
    {
      term_ = term;
      host_ = host;
      pass_ = pass;
      cancelled_ = false;
      Register();
      super(&Run);
    }

    void Run()// in a temporary thread other than the main thread
    {
      // try to input password for 10 seconds
      for(int i=0; i<20; ++i){
        if(cancelled_){
          break;
        }

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

        Thread.sleep(5_000_000);
      }

      // remove from ThreadList
      gdkThreadsEnter();
      Unregister();
      gdkThreadsLeave();
    }

    void Stop()
    {
      cancelled_ = true;
      Unregister();
    }

    string GetThreadListLabel(string startTime)
    {
      return "Waiting for password  query from " ~ host_ ~ " (" ~ startTime ~ ')';
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
    GtkTargetEntry[] dragTargets = constants.GetDragTargets() ~ GtkTargetEntry(Str.toStringz("text/plain"), 0, 2);
    DragAndDrop.destSet(
      this,
      GtkDestDefaults.ALL,
      dragTargets.ptr,
      cast(int)dragTargets.length,
      GdkDragAction.ACTION_MOVE | GdkDragAction.ACTION_COPY);
    addOnDragDataReceived(&DragDataReceived);
  }

  void DragDataReceived(
    GdkDragContext * context, int x, int y,
    GtkSelectionData * selection, uint info, uint time, Widget w)
  {
    if(info == 1){// URI list
      string[] paths = GetFilesFromSelection(selection);
      if(paths.length > 0){
        string s = " ";
        foreach(path; paths){
          s ~= EscapeSpecialChars(path) ~ ' ';
        }
        FeedChild(s);
      }
    }
    else if(info == 2){// plain text, feed the original text
      char * cstr = Selections.dataGetText(selection);
      string str = Str.toString(cstr);
      FeedChild(str);
    }

    auto dnd = new DragAndDrop(context);
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
                                         char *name);
  void vte_terminal_set_scrollback_lines(VteTerminal *terminal,
                                         glong lines);
  void vte_terminal_set_audible_bell(VteTerminal *terminal,
                                     gboolean is_audible);

  // IO between child process
  void vte_terminal_feed_child(VteTerminal *terminal,
                               char *text,
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
  pid_t vte_terminal_fork_command(VteTerminal * terminal, // deprecated
                                  char *command,
                                  char **argv,
                                  char **envv,
                                  char *directory,
                                  gboolean lastlog,
                                  gboolean utmp,
                                  gboolean wtmp);
  int vte_terminal_get_pty(VteTerminal * terminal); // deprecated

  // since 0.26
  enum VtePtyFlags;
  enum GSpawnFlags;
  alias int GPid;// the same type as pid_t
  alias extern(C) void function(gpointer user_data) GSpawnChildSetupFunc;
  gboolean vte_terminal_fork_command_full(VteTerminal *terminal,
                                          VtePtyFlags pty_flags,
                                          char *working_directory,
                                          char **argv,
                                          char **envv,
                                          GSpawnFlags spawn_flags,
                                          GSpawnChildSetupFunc child_setup,
                                          gpointer child_setup_data,
                                          GPid *child_pid,
                                          GError **error);

  struct VtePty;
  VtePty * vte_terminal_get_pty_object(VteTerminal *terminal);

  int vte_pty_get_fd(VtePty * pty);
}
