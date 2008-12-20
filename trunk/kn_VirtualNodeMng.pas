unit kn_VirtualNodeMng;

interface
uses
  kn_Const, TreeNT, kn_NodeList;

    // virtual nodes
    procedure VirtualNodeProc( VMode : TVirtualMode; myTreeNode : TTreeNTNode; VirtFN : string );
    procedure VirtualNodeRefresh( const DoPrompt : boolean );
    procedure VirtualNodeUnlink;
    function GetCurrentVirtualNode : TNoteNode;
    procedure VirtualNodeUpdateMenu( const IsVirtual : boolean );
    {$IFDEF WITH_IE}
    function VirtualNodeGetMode( const aNode : TNoteNode; var newMode : TVirtualMode; var newFN : string ) : boolean;
    {$ENDIF}

var
   Virtual_UnEncrypt_Warning_Done : boolean;

implementation

uses
   Dialogs, Controls, SysUtils,
   gf_files, gf_misc, kn_Global, kn_Main, kn_Info, kn_NoteObj, Kn_TreeNoteMng, kn_NoteFileMng;

{$IFDEF WITH_IE}
function VirtualNodeGetMode( const aNode : TNoteNode; var newMode : TVirtualMode; var newFN : string ) : boolean;
var
  Form_VNode : TForm_VNode;
begin
  result := false;
  if ( not assigned( aNode )) then exit;
  Form_VNode := TForm_VNode.Create( self );
  try
    Form_VNode.myVirtualMode := aNode.VirtualMode;
    Form_VNode.myVirtualFN := aNode.VirtualFN;
    Form_VNode.myNodeName := aNode.Name;
    if ( Form_VNode.ShowModal = mrOK ) then
    begin
      newMode := Form_VNode.myVirtualMode;
      newFN := Form_VNode.myVirtualFN;
      result := ( newFN <> '' );
    end;
  finally
    Form_VNode.Free;
  end;
end; // VirtualNodeGetMode
{$ENDIF}

procedure VirtualNodeProc( VMode : TVirtualMode; myTreeNode : TTreeNTNode; VirtFN : string );
var
  myNoteNode : TNoteNode;
  oldDlgFilter : string;
  ext : string;
  IsVNError, IsFlushingData, IsChangingFile : boolean;
begin
  myNoteNode := nil;
  if ( myTreeNode = nil ) then
    myTreeNode := GetCurrentTreeNode;
  if ( assigned( myTreeNode )) then
    myNoteNode := TNoteNode( myTreeNode.Data );

  if ( not assigned( myNoteNode )) then exit;
  IsFlushingData := false;
  IsChangingFile := false;
  IsVNError := false;

  if ( myNoteNode.VirtualMode <> vmNone ) then
  begin
    // Already a virtual node. Ask if user wants
    // to change the file with which the node is linked.
    // Do not prompt if there was an error loading the node
    // (in that case, assume the user DOES want to relink the node)

    {$IFDEF WITH_IE}
    IsChangingFile := true;
    {$ELSE}
    if myNoteNode.HasVNodeError then
    begin
      IsChangingFile := true;
      IsVNError := true;
    end
    else
    begin
      if ( messagedlg( Format(
      'Virtual node "%s" is currently linked to file "%s". Do you want to link the node to a different file?',
      [myNoteNode.Name, myNoteNode.VirtualFN] ),
      mtConfirmation, [mbOK, mbCancel], 0 ) = mrOK ) then
        IsChangingFile := true;
    end;

    {$ENDIF}

    if ( not IsChangingFile ) then
    begin
      exit;
    end;

  end
  else
  begin
    // not a virtual node. If it has text, we have to have an additional prompt
    if ( ActiveNote.Editor.Lines.Count > 0 ) then
    begin
      if ( messagedlg( Format(
        'Node "%s" contains text. Do you want to flush this text to a file and make the node virtual?',
        [myNoteNode.Name] ),
        mtConfirmation, [mbOK,mbCancel], 0 ) <> mrOK ) then
      exit;
      IsFlushingData := true; // needs a SaveDlg, not an OpenDlg
    end;

  end;

  with Form_Main do begin
      if (( NoteFile.FileFormat = nffEncrypted ) and ( not Virtual_UnEncrypt_Warning_Done )) then
      begin
        if ( messagedlg(
          'This KeyNote file is encrypted, but ' +
          'disk files linked to virtual nodes ' +
          'will NOT be encrypted.' + #13#13 + 'Continue?',
          mtWarning, [mbYes,mbNo], 0 ) <> mrYes ) then exit;
        Virtual_UnEncrypt_Warning_Done := true;
      end;

      if ( VirtFN = '' ) then
      begin

        if IsFlushingData then
        begin
          // use SaveDlg
          // never true for vmIELocal or vmIERemote
          oldDlgFilter := SaveDlg.Filter;
          SaveDlg.Filter := FILTER_RTFFILES + '|' + FILTER_TEXTFILES + '|' + FILTER_HTMLFILES + '|' + FILTER_ALLFILES;
          SaveDlg.Title := 'Select file for virtual node';
          SaveDlg.Filename := myNoteNode.Name;

          try
            if ( not SaveDlg.Execute ) then exit;
          finally
            SaveDlg.Filter := oldDlgFilter;
          end;
          VirtFN := SaveDlg.FileName;
          if ( extractfileext( VirtFN ) = '' ) then
            VirtFN := VirtFN + ext_RTF;
        end
        else
        begin
          {$IFDEF WITH_IE}
          if ( not VirtualNodeGetMode( myNoteNode, VMode, VirtFN )) then exit;
          {$ELSE}
          // use OpenDlg
          oldDlgFilter := OpenDlg.Filter;
          OpenDlg.Filter := FILTER_RTFFILES + '|' + FILTER_TEXTFILES + '|' + FILTER_HTMLFILES + '|' + FILTER_ALLFILES;
          OpenDlg.Title := 'Select file for virtual node';
          if IsVNError then
            OpenDlg.Filename := copy( myNoteNode.VirtualFN, 2, length( myNoteNode.VirtualFN ))
          else
            OpenDlg.Filename := myNoteNode.VirtualFN;

          try
            if ( not OpenDlg.Execute ) then exit;
          finally
            OpenDlg.Filter := oldDlgFilter;
          end;
          VirtFN := OpenDlg.FileName;
          {$ENDIF}
        end; // if IsFlushingData
      end; // if ( VirtFN = '' );

      if ( VMode <> vmIERemote ) then // do not smash case in URLs
      begin
        VirtFN := normalFN( VirtFN );

        if directoryexists( VirtFN ) then
        begin
          // not a file, but a directory - cannot import
          // (user could have drag-dropped a directory, so we must check)
          exit;
        end;

        // these following tests do not apply to IERemote nodes, either
        ext := extractfileext( VirtFN );
        if ( not ( ExtIsRTF( ext ) or ExtIsText( ext ) or ExtIsHTML( ext ))) then
        begin
          messagedlg( 'Only RTF, Text and HTML files can be linked to virtual nodes.', mtError, [mbOK], 0 );
          exit;
        end;

        // It is not reccommended to link files on virtual media (floppies,
        // CD-ROMs, ZIP drives, etc. So we check.
        if IsDriveRemovable( VirtFN ) then
        begin
          case TreeOptions.RemovableMediaVNodes of
            _REMOVABLE_MEDIA_VNODES_DENY : begin
              MessageDlg( Format(
                'Cannot link virtual node to a file on removable drive %s:\ ',
                [Extractfiledrive( VirtFN )] ), mtError, [mbOK], 0 );
              exit;
            end;
            _REMOVABLE_MEDIA_VNODES_WARN : begin
              if ( messagedlg( Format(
                'You are creating a virtual node linked to file on removable drive %s\. The file may not be available at a later time. Continue anyway?',
                [Extractfiledrive( VirtFN )] ), mtWarning, [mbOK,mbCancel], 0 ) <> mrOK ) then
                  exit;
            end;
            { _REMOVABLE_MEDIA_VNODES_ALLOW or any other value: allow }
          end;
        end;


        // any given file can be linked to a virtual node only once
        // per KNT file. So we must check if the selected file already
        // exists as a virtual node in the currently open KNT file.
        if NoteFile.HasVirtualNodeByFileName( myNoteNode, VirtFN ) then
        begin
          messagedlg( 'Selected file is already linked to a virtual node.', mtError, [mbOK], 0 );
          exit;
        end;

      end;

      try
        try

          ActiveNote.Editor.OnChange := nil;

          if ( IsChangingFile and ( not ( myNoteNode.VirtualMode in [vmIELocal, vmIERemote] ))) then
          begin
            // Node must save its existing data first:
            if ( not IsVNError ) then
            begin
              ActiveNote.EditorToDataStream;
              myNoteNode.SaveVirtualFile;
            end;
            // now clear the editor
            ActiveNote.Editor.Clear;
            ActiveNote.Editor.ClearUndo;
          end;

          {$IFDEF WITH_IE}
          myNoteNode.VirtualMode := VMode;
          myNoteNode.VirtualFN := VirtFN;
          {$ELSE}
          if ( myNoteNode.VirtualMode in [vmNone, vmText, vmRTF, vmHTML] ) then
            myNoteNode.VirtualMode := VMode; // so that setting new filename will adjust the vm type
          myNoteNode.VirtualFN := VirtFN;
          {$ENDIF}

          // myNoteNode.Stream.LoadFromFile( myNoteNode.VirtualFN );
          if IsFlushingData then
          begin
            // never true for vmIELocal or vmIERemote
            ActiveNote.EditorToDataStream;
            myNoteNode.SaveVirtualFile;
          end
          else
          begin
            myNoteNode.LoadVirtualFile;
            ActiveNote.DataStreamToEditor;
          end;
          VirtualNodeUpdateMenu( true );
          myTreeNode := GetCurrentTreeNode;
          SelectIconForNode( myTreeNode, TTreeNote( ActiveNote ).IconKind );
          if ( TreeOptions.AutoNameVNodes and ( not IsFlushingData )) then
          begin
            myNoteNode.Name := extractfilename( myNoteNode.VirtualFN ); // {N}
            (* [x] ImportFileNamesWithExt ignored for virtual nodes, because it is useful to have extension visible
            if KeyOptions.ImportFileNamesWithExt then
              myNoteNode.Name := extractfilename( myNoteNode.VirtualFN ) // {N}
            else
              myNoteNode.Name := extractfilenameNoExt( myNoteNode.VirtualFN );
            *)
            myTreeNode.Text := myNoteNode.Name;
          end;

        except
          on E : Exception do
          begin
            myNoteNode.VirtualFN := '';
            messagedlg( 'Virtual node error: ' + E.Message,
              mtError, [mbOK], 0 );
          end;
        end;

      finally

        NoteFile.Modified := true;
        UpdateNoteFileState( [fscModified] );
        ActiveNote.Editor.Modified := false;
        ActiveNote.Editor.OnChange := RxRTFChange;

      end;
  end;
end; // VirtualNodeProc


procedure VirtualNodeUnlink;
var
  myNoteNode : TNoteNode;
  myTreeNode : TTreeNTNode;
begin
  myNoteNode := GetCurrentVirtualNode;
  if ( not assigned( myNoteNode )) then exit;
  myTreeNode := GetCurrentTreeNode;
  if ( not assigned( myTreeNode )) then exit;

  // cannot unlink vmIERemote virtual nodes,
  // because there's no local file

  if ( myNoteNode.VirtualMode in [vmIELocal, vmIERemote] ) then
  begin
    messagedlg( Format(
      'Node "%s" represents an Internet Explorer node and cannot be unlinked. Nodes of this type can only be deleted.',
      [myNoteNode.Name] ), mtError, [mbOK], 0 );
    exit;
  end;

  if ( messagedlg( Format(
    'Unlink virtual node "%s"? The contents of the node will be retained, but the link with the file on disk (%s) will be removed.',
    [myNoteNode.Name, myNoteNode.VirtualFN] ),
    mtConfirmation, [mbOK, mbCancel], 0 ) = mrOK ) then
  begin
    try
      myNoteNode.VirtualMode := vmNone;
      myNoteNode.VirtualFN := '';
      ActiveNote.Modified := true;
      VirtualNodeUpdateMenu( false );
      SelectIconForNode( myTreeNode, TTreeNote( ActiveNote ).IconKind );
    finally
      NoteFile.Modified := true;
      UpdateNoteFileState( [fscModified] );
    end;
  end;

end; // VirtualNodeUnlink

procedure VirtualNodeRefresh( const DoPrompt : boolean );
var
  myNoteNode : TNoteNode;
begin
  myNoteNode := GetCurrentVirtualNode;
  if ( not assigned( myNoteNode )) then exit;

  // if ( ActiveNote.FocusMemory <> focTree ) then exit;

  if myNoteNode.RTFModified then
  begin
    if ( messagedlg( Format(
      'Virtual node %s HAS BEEN modified within KeyNote. ' +
      'If the node is refreshed, the changes will be lost. ' +
      'OK to reload the node from file %s?',
      [myNoteNode.Name, extractfilename( myNoteNode.VirtualFN )] ),
      mtWarning, [mbOK,mbCancel], 0 ) <> mrOK ) then
    exit;
  end
  else
  if DoPrompt then
  begin
    if ( messagedlg( Format(
      'Virtual node %s has NOT been modified within KeyNote. ' +
      'OK to reload the node from file %s?',
      [myNoteNode.Name, extractfilename( myNoteNode.VirtualFN )] ),
      mtConfirmation, [mbOK,mbCancel], 0 ) <> mrOK ) then
    exit;
  end;

  with Form_Main do begin
      ActiveNote.Editor.Lines.BeginUpdate;
      ActiveNote.Editor.OnChange := nil;
      try
        try
          myNoteNode.LoadVirtualFile;
        except
          on E : Exception do
          begin
            messagedlg( 'Error refreshing virtual node: ' + E.Message, mtError, [mbOK] , 0 );
            exit;
          end;
        end;

        try
          ActiveNote.Editor.Clear;
          ActiveNote.Editor.ClearUndo;
          ActiveNote.DataStreamToEditor;
          StatusBar.Panels[PANEL_HINT].Text := ' Virtual node refreshed.';
        except
          StatusBar.Panels[PANEL_HINT].Text := ' Error refreshing node';
        end;

      finally
        ActiveNote.Editor.Lines.EndUpdate;
        NoteFile.Modified := true;
        UpdateNoteFileState( [fscModified] );
        ActiveNote.Editor.OnChange := RxRTFChange;
      end;
  end;

end; // VirtualNodeRefresh

procedure VirtualNodeUpdateMenu( const IsVirtual : boolean );
begin
  with Form_Main do begin
      TVVirtualNode.Checked := IsVirtual;
      TVRefreshVirtualNode.Enabled := IsVirtual;
      TVUnlinkVirtualNode.Enabled := IsVirtual;
  end;
end; // VirtualNodeUpdateMenu

function GetCurrentVirtualNode : TNoteNode;
begin
  result := GetCurrentNoteNode;
  if ( result = nil ) then exit;
  if ( result.VirtualMode = vmNone ) then
  begin
    messagedlg( Format(
      'Selected node "%s" is not a virtual node.',
      [result.Name] ), mtError, [mbOK], 0 );
    result := nil;
  end;
end; // GetCurrentVirtualNode

initialization
  Virtual_UnEncrypt_Warning_Done := false;
end.
