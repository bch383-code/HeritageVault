import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import '../database/database_helper.dart';
import '../models/family_person.dart';
import '../models/heritage_story.dart';
import '../services/story_repository.dart';

class StoriesScreen extends StatefulWidget {
  final String? initialFilePath;
  final VoidCallback? onInitialFileConsumed;

  const StoriesScreen({
    super.key,
    this.initialFilePath,
    this.onInitialFileConsumed,
  });

  @override State<StoriesScreen> createState() => _StoriesScreenState();
}

class _StoriesScreenState extends State<StoriesScreen> {
  static const navy=Color(0xFF061725), panel=Color(0xFF0A2235),
      gold=Color(0xFFC9A65A), cream=Color(0xFFF3E9D1);
  final repo=StoryRepository.instance;
  final search=TextEditingController();
  List<HeritageStory> stories=const [];
  final Map<int,StoryAttachment?> covers={};
  final Map<int,List<FamilyPerson>> storyPeople={};
  bool loading=true;
  bool _quickCaptureHandled=false;

  @override
  void initState(){
    super.initState();
    load();
    WidgetsBinding.instance.addPostFrameCallback((_)=>_handleInitialFile());
  }
  @override void dispose(){search.dispose();super.dispose();}

  Future<void> load() async {
    final value=await repo.getStories(search:search.text);
    if(!mounted)return;
    final nextCovers=<int,StoryAttachment?>{};
    final nextPeople=<int,List<FamilyPerson>>{};
    for(final story in value){
      if(story.id!=null){
        nextCovers[story.id!]=await repo.getCoverAttachment(story.id!);
        nextPeople[story.id!]=await repo.getPeople(story.id!);
      }
    }
    if(!mounted)return;
    setState((){
      stories=value;
      covers
        ..clear()
        ..addAll(nextCovers);
      storyPeople
        ..clear()
        ..addAll(nextPeople);
      loading=false;
    });
  }

  Future<void> _handleInitialFile() async {
    if(_quickCaptureHandled)return;
    final path=widget.initialFilePath?.trim()??'';
    if(path.isEmpty)return;
    _quickCaptureHandled=true;
    widget.onInitialFileConsumed?.call();

    if(!File(path).existsSync()){
      if(!mounted)return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content:Text('The selected story file could not be found.')),
      );
      return;
    }

    await edit(null,path);
  }

  Future<void> edit([HeritageStory? story,String? initialAttachmentPath]) async {
    final changed=await showDialog<bool>(
      context:context, barrierDismissible:false,
      builder:(_)=>_StoryEditorDialog(
        story:story,
        initialAttachmentPath:initialAttachmentPath,
      ));
    if(changed==true)await load();
  }

  Future<void> remove(HeritageStory story) async {
    final yes=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(
      title:const Text('Delete Story?'),
      content:Text('Delete “${story.title}”?'),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Cancel')),
        FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Delete')),
      ]));
    if(yes==true&&story.id!=null){await repo.deleteStory(story.id!);await load();}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: navy,
      appBar: AppBar(
        backgroundColor: navy,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Stories',
          style: TextStyle(color: cream, fontWeight: FontWeight.w800),
        ),
        actions: [
          FilledButton.icon(
            onPressed: () => edit(),
            icon: const Icon(Icons.note_add_outlined),
            label: const Text('NEW STORY'),
          ),
          const SizedBox(width: 18),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: panel.withValues(alpha: .88),
                border: Border.all(color: gold.withValues(alpha: .28)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Row(
                children: [
                  Icon(Icons.auto_stories_outlined, color: gold, size: 38),
                  SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Family Story Archive',
                          style: TextStyle(
                            color: cream,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 5),
                        Text(
                          'Preserve the memories behind the people and things.',
                          style: TextStyle(color: Color(0xFFAAB8C2)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: search,
                    onChanged: (_) {
                      setState(() {});
                      load();
                    },
                    style: const TextStyle(color: cream),
                    decoration: InputDecoration(
                      hintText: 'Search stories, places, dates, or text...',
                      hintStyle: const TextStyle(color: Color(0xFFAAB8C2)),
                      prefixIcon: const Icon(Icons.search, color: gold),
                      suffixIcon: search.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                search.clear();
                                setState(() {});
                                load();
                              },
                            ),
                      filled: true,
                      fillColor: panel.withValues(alpha: .72),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide(
                          color: gold.withValues(alpha: .25),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 190,
                  child: DropdownButtonFormField<String>(
                    initialValue: 'All',
                    dropdownColor: panel,
                    style: const TextStyle(color: cream),
                    decoration: InputDecoration(
                      labelText: 'Type',
                      labelStyle: const TextStyle(color: Color(0xFFAAB8C2)),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                          color: gold.withValues(alpha: .35),
                        ),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderSide: BorderSide(color: gold),
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'All',
                        child: Text('All'),
                      ),
                    ],
                    onChanged: (_) {},
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : stories.isEmpty
                      ? Center(
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 620),
                            padding: const EdgeInsets.all(36),
                            decoration: BoxDecoration(
                              color: panel,
                              border: Border.all(
                                color: gold.withValues(alpha: .35),
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.menu_book_outlined,
                                  color: gold,
                                  size: 54,
                                ),
                                SizedBox(height: 14),
                                Text(
                                  'Your story archive is ready.',
                                  style: TextStyle(
                                    color: cream,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'Record a memory, oral history, or the story behind an heirloom.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Color(0xFFB8C7D1),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.separated(
                          itemCount: stories.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, i) => _card(stories[i]),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(HeritageStory s) {
    final attachment=(s.id==null
        ?s.attachmentPath
        :(covers[s.id!]?.path??s.attachmentPath)).trim();
    final hasAttachment=attachment.isNotEmpty;
    final file=hasAttachment?File(attachment):null;
    final exists=file?.existsSync()??false;
    final ext=hasAttachment
        ?attachment.split('.').last.toLowerCase()
        :'';
    final isImage=exists&&const{
      'jpg','jpeg','png','tif','tiff'
    }.contains(ext);
    final meta=[s.dateText,s.place,s.authorSource]
        .where((e)=>e.trim().isNotEmpty)
        .join(' • ');

    return InkWell(
      onTap:()=>edit(s),
      borderRadius:BorderRadius.circular(5),
      child:Container(
        height:214,
        decoration:BoxDecoration(
          color:panel,
          border:Border.all(color:gold.withValues(alpha:.34)),
          borderRadius:BorderRadius.circular(5),
        ),
        clipBehavior:Clip.antiAlias,
        child:Row(children:[
          SizedBox(
            width:250,
            height:214,
            child:isImage
                ?Image.file(
                    file!,
                    fit:BoxFit.cover,
                    errorBuilder:(_,error,stackTrace)=>_storyDocumentPreview(ext,exists),
                  )
                :exists&&ext=='pdf'
                    ?_pdfStoryPreview(attachment)
                    :exists&&const{'doc','docx'}.contains(ext)
                        ?_wordStoryPreview(attachment)
                        :_storyDocumentPreview(ext,exists),
          ),
          Expanded(
            child:Padding(
              padding:const EdgeInsets.fromLTRB(22,18,10,16),
              child:Column(
                crossAxisAlignment:CrossAxisAlignment.start,
                children:[
                  Row(children:[
                    Expanded(
                      child:Text(
                        s.title,
                        maxLines:1,
                        overflow:TextOverflow.ellipsis,
                        style:const TextStyle(
                          color:cream,
                          fontSize:20,
                          fontWeight:FontWeight.w900,
                          letterSpacing:.2,
                        ),
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip:'Story actions',
                      onSelected:(v){
                        if(v=='edit')edit(s);
                        if(v=='delete')remove(s);
                      },
                      itemBuilder:(_)=>const[
                        PopupMenuItem(value:'edit',child:Text('Edit')),
                        PopupMenuItem(value:'delete',child:Text('Delete')),
                      ],
                    ),
                  ]),
                  if(meta.isNotEmpty)...[
                    const SizedBox(height:4),
                    Text(
                      meta,
                      maxLines:1,
                      overflow:TextOverflow.ellipsis,
                      style:const TextStyle(
                        color:gold,
                        fontWeight:FontWeight.w700,
                      ),
                    ),
                  ],
                  if(s.id!=null&&(storyPeople[s.id!]??const <FamilyPerson>[]).isNotEmpty)...[
                    const SizedBox(height:8),
                    Row(
                      crossAxisAlignment:CrossAxisAlignment.start,
                      children:[
                        const Icon(Icons.people_outline,color:Color(0xFFB8C7D1),size:16),
                        const SizedBox(width:6),
                        Expanded(
                          child:Text(
                            'People: ${(storyPeople[s.id!]??const <FamilyPerson>[]).map((p)=>p.displayName).join(' • ')}',
                            maxLines:1,
                            overflow:TextOverflow.ellipsis,
                            style:const TextStyle(
                              color:Color(0xFFB8C7D1),
                              fontSize:12,
                              fontWeight:FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height:8),
                  Expanded(
                    child:Text(
                      s.storyText.trim().isEmpty
                          ?'Open this story to add the memory behind it.'
                          :s.storyText.trim(),
                      maxLines:4,
                      overflow:TextOverflow.ellipsis,
                      style:const TextStyle(
                        color:Color(0xFFD8DDE0),
                        height:1.45,
                        fontSize:14,
                      ),
                    ),
                  ),
                  Row(children:[
                    const Icon(
                      Icons.auto_stories_outlined,
                      color:gold,
                      size:17,
                    ),
                    const SizedBox(width:7),
                    const Text(
                      'READ STORY',
                      style:TextStyle(
                        color:cream,
                        fontSize:12,
                        fontWeight:FontWeight.w900,
                        letterSpacing:1.0,
                      ),
                    ),
                    if(hasAttachment)...[
                      const SizedBox(width:18),
                      Icon(
                        isImage
                            ?Icons.photo_outlined
                            :Icons.description_outlined,
                        color:const Color(0xFFB8C7D1),
                        size:16,
                      ),
                      const SizedBox(width:5),
                      Text(
                        isImage?'PHOTO':'SOURCE FILE',
                        style:const TextStyle(
                          color:Color(0xFFB8C7D1),
                          fontSize:11,
                          fontWeight:FontWeight.w700,
                        ),
                      ),
                    ],
                  ]),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _pdfStoryPreview(String path){
    return ColoredBox(
      color:const Color(0xFFE8E1D4),
      child:PdfDocumentViewBuilder.file(
        path,
        loadingBuilder:(context)=>const Center(
          child:SizedBox(
            width:28,
            height:28,
            child:CircularProgressIndicator(strokeWidth:2),
          ),
        ),
        errorBuilder:(context,error,stackTrace)=>
            _storyDocumentPreview('pdf',true),
        builder:(context,document){
          if(document==null||document.pages.isEmpty){
            return _storyDocumentPreview('pdf',true);
          }
          return Stack(
            fit:StackFit.expand,
            children:[
              PdfPageView(
                document:document,
                pageNumber:1,
                alignment:Alignment.center,
              ),
              Positioned(
                left:10,
                bottom:10,
                child:Container(
                  padding:const EdgeInsets.symmetric(
                    horizontal:8,
                    vertical:4,
                  ),
                  decoration:BoxDecoration(
                    color:const Color(0xFF061725).withValues(alpha:.86),
                    border:Border.all(
                      color:gold.withValues(alpha:.55),
                    ),
                    borderRadius:BorderRadius.circular(3),
                  ),
                  child:const Row(
                    mainAxisSize:MainAxisSize.min,
                    children:[
                      Icon(
                        Icons.picture_as_pdf_outlined,
                        color:gold,
                        size:13,
                      ),
                      SizedBox(width:5),
                      Text(
                        'PDF',
                        style:TextStyle(
                          color:cream,
                          fontSize:10,
                          fontWeight:FontWeight.w900,
                          letterSpacing:.8,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _wordStoryPreview(String path){
    return FutureBuilder<String?>(
      future:_wordPreviewPdf(path),
      builder:(context,snapshot){
        final pdfPath=snapshot.data;
        if(snapshot.connectionState==ConnectionState.waiting){
          return const ColoredBox(
            color:Color(0xFFE8E1D4),
            child:Center(child:Column(
              mainAxisSize:MainAxisSize.min,
              children:[
                SizedBox(width:28,height:28,child:CircularProgressIndicator(strokeWidth:2)),
                SizedBox(height:10),
                Text('PREPARING WORD PREVIEW',style:TextStyle(
                  color:Color(0xFF061725),fontSize:10,fontWeight:FontWeight.w900,letterSpacing:.8)),
              ],
            )),
          );
        }
        if(pdfPath==null||pdfPath.isEmpty||!File(pdfPath).existsSync()){
          return _storyDocumentPreview(path.split('.').last.toLowerCase(),true);
        }
        return Stack(fit:StackFit.expand,children:[
          _pdfStoryPreview(pdfPath),
          Positioned(right:10,bottom:10,child:Container(
            padding:const EdgeInsets.symmetric(horizontal:8,vertical:4),
            decoration:BoxDecoration(
              color:const Color(0xFF061725).withValues(alpha:.86),
              border:Border.all(color:gold.withValues(alpha:.55)),
              borderRadius:BorderRadius.circular(3),
            ),
            child:const Row(mainAxisSize:MainAxisSize.min,children:[
              Icon(Icons.description_outlined,color:gold,size:13),
              SizedBox(width:5),
              Text('WORD',style:TextStyle(
                color:cream,fontSize:10,fontWeight:FontWeight.w900,letterSpacing:.8)),
            ]),
          )),
        ]);
      },
    );
  }

  Future<String?> _wordPreviewPdf(String sourcePath) async {
    if(!Platform.isWindows)return null;
    final source=File(sourcePath);
    if(!source.existsSync())return null;

    try{
      final cacheDir=Directory(
        '${Directory.systemTemp.path}${Platform.pathSeparator}heirloom_atlas_story_previews',
      );
      if(!cacheDir.existsSync()){
        cacheDir.createSync(recursive:true);
      }

      final stat=source.statSync();
      final safeKey=
          '${sourcePath.hashCode.abs()}_${stat.modified.millisecondsSinceEpoch}';
      final outputPath=
          '${cacheDir.path}${Platform.pathSeparator}word_$safeKey.pdf';
      final output=File(outputPath);

      if(output.existsSync()&&output.lengthSync()>0){
        return outputPath;
      }

      String psQuote(String value) => "'${value.replaceAll("'", "''")}'";

      final script = '''
\$ErrorActionPreference = 'Stop'
\$word = \$null
\$doc = \$null
try {
  \$word = New-Object -ComObject Word.Application
  \$word.Visible = \$false
  \$word.DisplayAlerts = 0
  \$doc = \$word.Documents.Open(${psQuote(sourcePath)}, \$false, \$true)
  \$doc.ExportAsFixedFormat(${psQuote(outputPath)}, 17)
} finally {
  if (\$doc -ne \$null) { \$doc.Close(\$false) }
  if (\$word -ne \$null) { \$word.Quit() }
}
''';

      final result=await Process.run(
        'powershell.exe',
        [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          script,
        ],
        runInShell:false,
      ).timeout(const Duration(seconds:20));

      if(result.exitCode==0&&output.existsSync()&&output.lengthSync()>0){
        return outputPath;
      }
    }catch(_){
      // If Microsoft Word is unavailable, keep the archival fallback preview.
    }

    return null;
  }

  Widget _storyDocumentPreview(String ext,bool exists){
    final label=!exists&&ext.isNotEmpty
        ?'SOURCE FILE MISSING'
        :switch(ext){
          'pdf'=>'PDF DOCUMENT',
          'doc'||'docx'=>'WORD DOCUMENT',
          'txt'=>'TEXT DOCUMENT',
          'rtf'=>'RTF DOCUMENT',
          'tif'||'tiff'=>'SCANNED IMAGE',
          _=>'FAMILY STORY',
        };

    final icon=!exists&&ext.isNotEmpty
        ?Icons.link_off_outlined
        :switch(ext){
          'pdf'=>Icons.picture_as_pdf_outlined,
          'doc'||'docx'=>Icons.description_outlined,
          'txt'||'rtf'=>Icons.article_outlined,
          _=>Icons.auto_stories_outlined,
        };

    return DecoratedBox(
      decoration:const BoxDecoration(
        color:Color(0xFF0D2A40),
      ),
      child:Stack(children:[
        Positioned.fill(
          child:CustomPaint(painter:_ArchiveLinesPainter()),
        ),
        Center(
          child:Column(
            mainAxisSize:MainAxisSize.min,
            children:[
              Icon(icon,color:gold,size:48),
              const SizedBox(height:12),
              Padding(
                padding:const EdgeInsets.symmetric(horizontal:16),
                child:Text(
                  label,
                  textAlign:TextAlign.center,
                  style:const TextStyle(
                    color:cream,
                    fontSize:11,
                    fontWeight:FontWeight.w900,
                    letterSpacing:1.15,
                  ),
                ),
              ),
              if(ext.isNotEmpty)...[
                const SizedBox(height:5),
                Text(
                  ext.toUpperCase(),
                  style:const TextStyle(
                    color:Color(0xFF9EB0BC),
                    fontSize:10,
                    fontWeight:FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ]),
    );
  }

}


class _ArchiveLinesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas,Size size){
    final paint=Paint()
      ..color=const Color(0xFFC9A65A).withValues(alpha:.07)
      ..strokeWidth=1;
    for(double y=18;y<size.height;y+=22){
      canvas.drawLine(Offset(0,y),Offset(size.width,y),paint);
    }
    final border=Paint()
      ..color=const Color(0xFFC9A65A).withValues(alpha:.18)
      ..style=PaintingStyle.stroke
      ..strokeWidth=1;
    canvas.drawRect(
      Rect.fromLTWH(12,12,size.width-24,size.height-24),
      border,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate)=>false;
}


class _StoryEditorDialog extends StatefulWidget {
  final HeritageStory? story;
  final String? initialAttachmentPath;

  const _StoryEditorDialog({
    this.story,
    this.initialAttachmentPath,
  });
  @override State<_StoryEditorDialog> createState()=>_StoryEditorDialogState();
}

class _StoryEditorDialogState extends State<_StoryEditorDialog> {
  final repo=StoryRepository.instance, db=DatabaseHelper.instance;
  late final TextEditingController title,text,date,place,source,notes;
  List<String> attachments=[];
  String coverPath='';
  List<FamilyPerson> people=const [];
  Set<int> selected={};
  bool saving=false;
  bool loadingPeople=true;

  @override void initState(){
    super.initState(); final s=widget.story;
    final initialPath=widget.initialAttachmentPath?.trim()??'';
    final initialName=initialPath.isEmpty
        ?''
        :initialPath.split(RegExp(r'[\\/]')).last;
    final suggestedTitle=initialName.contains('.')
        ?initialName.substring(0,initialName.lastIndexOf('.'))
        :initialName;
    title=TextEditingController(text:s?.title??suggestedTitle);
    text=TextEditingController(text:s?.storyText??'');
    date=TextEditingController(text:s?.dateText??'');
    place=TextEditingController(text:s?.place??'');
    source=TextEditingController(text:s?.authorSource??'');
    notes=TextEditingController(text:s?.notes??'');
    final legacy=s?.attachmentPath.trim()??'';
    if(legacy.isNotEmpty){
      attachments=[legacy];
      coverPath=legacy;
    }else if(initialPath.isNotEmpty){
      attachments=[initialPath];
      coverPath=initialPath;
    }
    loadPeople();
    loadAttachments();
  }

  Future<void> loadAttachments() async {
    final id=widget.story?.id;
    if(id==null)return;
    final items=await repo.getAttachments(id);
    if(!mounted)return;
    setState((){
      attachments=items.map((e)=>e.path).toList();
      final covers=items.where((e)=>e.isCover).toList();
      coverPath=covers.isNotEmpty
          ?covers.first.path
          :(attachments.isEmpty?'':attachments.first);
    });
  }

  Future<void> loadPeople() async {
    final p=await db.getFamilyPeople();
    final ids=widget.story?.id==null
        ?<int>{}
        :(await repo.getPersonIds(widget.story!.id!)).toSet();
    if(!mounted)return;
    setState((){
      people=p;
      selected=ids;
      loadingPeople=false;
    });
  }

  Future<void> choosePeople() async {
    if(loadingPeople)return;

    final working=Set<int>.from(selected);
    var query='';

    final result=await showDialog<Set<int>>(
      context:context,
      builder:(dialogContext)=>StatefulBuilder(
        builder:(context,setDialogState){
          final normalized=query.trim().toLowerCase();
          final filtered=normalized.isEmpty
              ?people
              :people.where((person)=>
                  person.displayName.toLowerCase().contains(normalized)
                ).toList();

          return Dialog(
            child:SizedBox(
              width:620,
              height:650,
              child:Column(
                children:[
                  Padding(
                    padding:const EdgeInsets.fromLTRB(20,16,10,12),
                    child:Row(
                      children:[
                        Expanded(
                          child:Column(
                            crossAxisAlignment:CrossAxisAlignment.start,
                            children:[
                              Text(
                                'Choose Family Tree People',
                                style:Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight:FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height:3),
                              Text(
                                '${working.length} selected',
                                style:Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip:'Close',
                          onPressed:()=>Navigator.pop(dialogContext),
                          icon:const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height:1),
                  Padding(
                    padding:const EdgeInsets.all(14),
                    child:TextField(
                      autofocus:true,
                      onChanged:(value){
                        query=value;
                        setDialogState((){});
                      },
                      decoration:const InputDecoration(
                        hintText:'Search family tree people...',
                        prefixIcon:Icon(Icons.search),
                        border:OutlineInputBorder(),
                      ),
                    ),
                  ),
                  Expanded(
                    child:filtered.isEmpty
                        ?const Center(child:Text('No matching people found.'))
                        :ListView.builder(
                            itemCount:filtered.length,
                            itemBuilder:(context,index){
                              final person=filtered[index];
                              final id=person.id;
                              if(id==null)return const SizedBox.shrink();
                              final checked=working.contains(id);
                              return CheckboxListTile(
                                value:checked,
                                dense:true,
                                title:Text(person.displayName),
                                onChanged:(value){
                                  setDialogState((){
                                    if(value==true){
                                      working.add(id);
                                    }else{
                                      working.remove(id);
                                    }
                                  });
                                },
                              );
                            },
                          ),
                  ),
                  const Divider(height:1),
                  Padding(
                    padding:const EdgeInsets.all(12),
                    child:Row(
                      children:[
                        TextButton(
                          onPressed:working.isEmpty
                              ?null
                              :()=>setDialogState(()=>working.clear()),
                          child:const Text('Clear'),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed:()=>Navigator.pop(dialogContext),
                          child:const Text('Cancel'),
                        ),
                        const SizedBox(width:8),
                        FilledButton(
                          onPressed:()=>Navigator.pop(
                            dialogContext,
                            Set<int>.from(working),
                          ),
                          child:const Text('Use Selected People'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    if(result==null||!mounted)return;
    setState(()=>selected=result);
  }

  @override
  void dispose(){
    title.dispose();
    text.dispose();
    date.dispose();
    place.dispose();
    source.dispose();
    notes.dispose();
    super.dispose();
  }

  Future<void> pick() async {
    final file=await FilePicker.pickFile(
      type:FileType.custom,
      allowedExtensions:const[
        'pdf','doc','docx','txt','rtf','jpg','jpeg','png','tif','tiff','heic'
      ],
    );
    final path=file?.path?.trim();
    if(path==null||path.isEmpty||!mounted)return;
    setState((){
      if(!attachments.contains(path))attachments.add(path);
      if(coverPath.isEmpty&&attachments.isNotEmpty){
        coverPath=attachments.first;
      }
    });
  }

  Future<void> save() async {
    if(title.text.trim().isEmpty)return;
    setState(()=>saving=true);
    await repo.saveStory(HeritageStory(
      id:widget.story?.id,title:title.text,storyText:text.text,dateText:date.text,
      place:place.text,authorSource:source.text,notes:notes.text,
      attachmentPath:coverPath,
      createdAtMilliseconds:widget.story?.createdAtMilliseconds??0,
    ),
      personIds:selected,
      attachmentPaths:attachments,
      coverPath:coverPath,
    );
    if(mounted)Navigator.pop(context,true);
  }

  @override Widget build(BuildContext context)=>Dialog(child:SizedBox(
    width:920,height:760,
    child:Column(children:[
      Padding(padding:const EdgeInsets.fromLTRB(22,18,12,12),child:Row(children:[
        Expanded(child:Text(widget.story==null?'New Story':'Edit Story',
          style:Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight:FontWeight.w900))),
        IconButton(onPressed:()=>Navigator.pop(context,false),icon:const Icon(Icons.close)),
      ])),
      const Divider(height:1),
      Expanded(child:ListView(padding:const EdgeInsets.all(22),children:[
        TextField(controller:title,decoration:const InputDecoration(labelText:'Story Title')),
        const SizedBox(height:14),
        TextField(controller:text,minLines:8,maxLines:16,decoration:const InputDecoration(labelText:'Story',alignLabelWithHint:true)),
        const SizedBox(height:14),
        Row(children:[
          Expanded(child:TextField(controller:date,decoration:const InputDecoration(labelText:'Date or Time Period'))),
          const SizedBox(width:12),
          Expanded(child:TextField(controller:place,decoration:const InputDecoration(labelText:'Place'))),
        ]),
        const SizedBox(height:14),
        TextField(controller:source,decoration:const InputDecoration(labelText:'Author / Source')),
        const SizedBox(height:14),
        TextField(controller:notes,minLines:2,maxLines:5,decoration:const InputDecoration(labelText:'Notes / Provenance')),
        const SizedBox(height:20),
        Text('Family Tree People',style:Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight:FontWeight.w900)),
        const SizedBox(height:8),
        Row(
          children:[
            Expanded(
              child:Text(
                loadingPeople
                    ?'Loading family tree people...'
                    :selected.isEmpty
                        ?'No people linked yet.'
                        :'${selected.length} ${selected.length==1?'person':'people'} linked.',
              ),
            ),
            OutlinedButton.icon(
              onPressed:loadingPeople?null:choosePeople,
              icon:loadingPeople
                  ?const SizedBox(
                      width:16,
                      height:16,
                      child:CircularProgressIndicator(strokeWidth:2),
                    )
                  :const Icon(Icons.people_outline),
              label:Text(selected.isEmpty?'Choose People':'Change People'),
            ),
          ],
        ),
        if(!loadingPeople&&selected.isNotEmpty)...[
          const SizedBox(height:10),
          Wrap(
            spacing:8,
            runSpacing:8,
            children:people.where((p)=>p.id!=null&&selected.contains(p.id)).map((p)=>
              InputChip(
                label:Text(p.displayName),
                onDeleted:()=>setState(()=>selected.remove(p.id)),
              )
            ).toList(),
          ),
        ],
        const SizedBox(height:20),
        Row(children:[
          Expanded(
            child:Column(
              crossAxisAlignment:CrossAxisAlignment.start,
              children:[
                Text(
                  'Supporting Materials',
                  style:Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight:FontWeight.w900,
                  ),
                ),
                const SizedBox(height:3),
                Text(
                  attachments.isEmpty
                      ?'Add photos, scanned documents, PDFs, Word files, or other source material.'
                      :'${attachments.length} ${attachments.length==1?'attachment':'attachments'} • choose one as the story cover',
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed:pick,
            icon:const Icon(Icons.add),
            label:const Text('Add Files'),
          ),
        ]),
        if(attachments.isNotEmpty)...[
          const SizedBox(height:10),
          RadioGroup<String>(
            groupValue:coverPath,
            onChanged:(value){
              if(value!=null)setState(()=>coverPath=value);
            },
            child:Column(
              children:[
                for(final path in attachments)
                  Card(
                    margin:const EdgeInsets.only(bottom:8),
                    child:ListTile(
                      dense:true,
                      leading:Radio<String>(value:path),
                      title:Text(
                        path.split(RegExp(r'[\\/]')).last,
                        maxLines:1,
                        overflow:TextOverflow.ellipsis,
                      ),
                      subtitle:Text(
                        path==coverPath
                            ?'STORY COVER'
                            :(!File(path).existsSync()?'Source file missing':path),
                        maxLines:1,
                        overflow:TextOverflow.ellipsis,
                      ),
                      trailing:IconButton(
                        tooltip:'Remove attachment',
                        onPressed:(){
                          setState((){
                            attachments.remove(path);
                            if(coverPath==path){
                              coverPath=attachments.isEmpty?'':attachments.first;
                            }
                          });
                        },
                        icon:const Icon(Icons.close),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ])),
      const Divider(height:1),
      Padding(padding:const EdgeInsets.all(14),child:Row(mainAxisAlignment:MainAxisAlignment.end,children:[
        TextButton(onPressed:saving?null:()=>Navigator.pop(context,false),child:const Text('Cancel')),
        const SizedBox(width:8),
        FilledButton.icon(onPressed:saving?null:save,icon:const Icon(Icons.save_outlined),label:Text(saving?'Saving...':'Save Story')),
      ])),
    ]),
  ));
}