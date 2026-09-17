import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../database/database_helper.dart';
import '../models/antique.dart';
import '../models/family_person.dart';
import 'family_person_screen.dart';

class AntiqueEditScreen extends StatefulWidget {
  final Antique? antique;
  final List<String> initialImagePaths;

  const AntiqueEditScreen({
    super.key,
    this.antique,
    this.initialImagePaths = const [],
  });

  @override
  State<AntiqueEditScreen> createState() => _AntiqueEditScreenState();
}

class _AntiqueEditScreenState extends State<AntiqueEditScreen> {
  final _db = DatabaseHelper.instance;
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _title, _description, _year, _acquiredFrom;
  late final TextEditingController _purchasePrice, _estimatedValue, _notes;
  late final TextEditingController _conditionNotes, _provenance;
  late final TextEditingController _appraisalSource, _valuationDate, _research;
  late List<String> _images, _documents;
  String _condition = '';
  List<FamilyPerson> _familyPeople = const [];
  Set<int> _selectedPeople = {};
  bool _saving = false;

  bool get _editing => widget.antique?.id != null;

  @override
  void initState() {
    super.initState();
    final a = widget.antique;
    _title = TextEditingController(text: a?.title ?? '');
    _description = TextEditingController(text: a?.description ?? '');
    _year = TextEditingController(text: a?.year ?? '');
    _acquiredFrom = TextEditingController(text: a?.acquiredFrom ?? '');
    _purchasePrice = TextEditingController(text: a?.purchasePrice?.toStringAsFixed(2) ?? '');
    _estimatedValue = TextEditingController(text: a?.estimatedValue?.toStringAsFixed(2) ?? '');
    _notes = TextEditingController(text: a?.notes ?? '');
    _conditionNotes = TextEditingController(text: a?.conditionNotes ?? '');
    _provenance = TextEditingController(text: a?.provenance ?? '');
    _appraisalSource = TextEditingController(text: a?.appraisalSource ?? '');
    _valuationDate = TextEditingController(text: a?.valuationDate ?? '');
    _condition = a?.condition ?? '';
    _images = [...?a?.imagePaths];
    _documents = [...?a?.supportingDocumentPaths];
    _research = TextEditingController(text: _buildResearchQuery());
    _loadFamily();
    _importInitialImages();
  }

  Future<void> _importInitialImages() async {
    if (widget.initialImagePaths.isEmpty) return;

    final root = await getApplicationDocumentsDirectory();
    final dir = Directory(
      path.join(root.path, 'Heirloom Atlas', 'Antiques', 'Images'),
    );
    await dir.create(recursive: true);

    final added = <String>[];
    for (var i = 0; i < widget.initialImagePaths.length; i++) {
      final sourcePath = widget.initialImagePaths[i];
      final source = File(sourcePath);
      if (!await source.exists()) continue;

      final destination = path.join(
        dir.path,
        'antique_quick_${DateTime.now().microsecondsSinceEpoch}_$i'
        '${path.extension(sourcePath)}',
      );
      await source.copy(destination);
      added.add(destination);
    }

    if (!mounted || added.isEmpty) return;
    setState(() => _images.addAll(added));
  }

  @override
  void dispose() {
    for (final c in [_title,_description,_year,_acquiredFrom,_purchasePrice,
      _estimatedValue,_notes,_conditionNotes,_provenance,_appraisalSource,
      _valuationDate,_research]) {
      c.dispose();
    }
    super.dispose();
  }

  double? _money(String value) {
    final clean = value.replaceAll(r'$', '').replaceAll(',', '').trim();
    return clean.isEmpty ? null : double.tryParse(clean);
  }

  String _buildResearchQuery() {
    final a = widget.antique;
    final title = _title.text.trim().isNotEmpty ? _title.text.trim() : (a?.title ?? '');
    final year = _year.text.trim().isNotEmpty ? _year.text.trim() : (a?.year ?? '');
    final desc = _description.text.trim().isNotEmpty ? _description.text.trim() : (a?.description ?? '');
    final words = desc.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).take(10).join(' ');
    return [title, year, words].where((e) => e.trim().isNotEmpty).join(' ').trim();
  }

  void _refreshResearch() {
    final q = _buildResearchQuery();
    setState(() {
      _research.text = q;
      _research.selection = TextSelection.collapsed(offset: q.length);
    });
  }

  String? _query() {
    if (_research.text.trim().isEmpty) _refreshResearch();
    final q = _research.text.trim();
    if (q.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter identifying details first.')),
      );
      return null;
    }
    return q;
  }

  Future<void> _launch(Uri uri, String label) async {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open $label.')));
    }
  }

  Future<void> _search(String kind) async {
    final q = _query();
    if (q == null) return;
    late Uri uri;
    switch (kind) {
      case 'images':
        uri = Uri.https('www.google.com','/search',{'q':q,'tbm':'isch'});
      case 'ebay':
        uri = Uri.https('www.ebay.com','/sch/i.html',{'_nkw':q,'_sacat':'0'});
      case 'sold':
        uri = Uri.https('www.ebay.com','/sch/i.html',{'_nkw':q,'_sacat':'0','LH_Complete':'1','LH_Sold':'1'});
      case 'etsy':
        uri = Uri.https('www.etsy.com','/search',{'q':q});
      case 'auction':
        uri = Uri.https('www.google.com','/search',{'q':'$q (site:liveauctioneers.com OR site:invaluable.com OR site:worthpoint.com)'});
      default:
        uri = Uri.https('www.google.com','/search',{'q':q});
    }
    await _launch(uri, kind);
  }


  Future<void> _searchResearchOnline() async {
    final q = _query();
    if (q == null) return;

    final urls = <Uri>[
      Uri.https('www.google.com', '/search', {'q': q}),
      Uri.https('www.google.com', '/search', {'q': q, 'tbm': 'isch'}),
      Uri.https('www.ebay.com', '/sch/i.html', {'_nkw': q, '_sacat': '0'}),
      Uri.https(
        'www.ebay.com',
        '/sch/i.html',
        {'_nkw': q, '_sacat': '0', 'LH_Complete': '1', 'LH_Sold': '1'},
      ),
    ];

    // Launch each destination externally. The browser decides whether these
    // appear as tabs in one window or as separate windows based on its settings.
    for (final uri in urls) {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('One of the research sites could not be opened.')),
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  Future<void> _loadFamily() async {
    final people = await _db.getFamilyPeople();
    final id = widget.antique?.id;
    final linked = id == null ? <FamilyPerson>[] : await _db.getFamilyPeopleForItem(
      itemType:'antique', itemKey:id.toString());
    if (!mounted) return;
    setState(() {
      _familyPeople = people;
      _selectedPeople = linked.map((p)=>p.id).whereType<int>().toSet();
    });
  }

  Future<void> _chooseFamily() async {
    if (_familyPeople.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add people to the Family Tree first.')));
      return;
    }
    final selected = {..._selectedPeople};
    var query = '';
    final result = await showDialog<Set<int>>(
      context: context,
      builder: (dc) => StatefulBuilder(builder: (context,setDialogState) {
        final q=query.trim().toLowerCase();
        final visible=_familyPeople.where((p)=>q.isEmpty||p.displayName.toLowerCase().contains(q)).toList();
        return Dialog(child:SizedBox(width:700,height:650,child:Column(children:[
          Padding(padding:const EdgeInsets.fromLTRB(20,16,8,10),child:Row(children:[
            const Icon(Icons.account_tree_outlined),const SizedBox(width:10),
            const Expanded(child:Text('Family Connections',style:TextStyle(fontSize:20,fontWeight:FontWeight.w900))),
            IconButton(onPressed:()=>Navigator.pop(dc),icon:const Icon(Icons.close)),
          ])),
          const Divider(height:1),
          Padding(padding:const EdgeInsets.all(14),child:TextField(
            autofocus:true,onChanged:(v)=>setDialogState(()=>query=v),
            decoration:const InputDecoration(hintText:'Search Family Tree...',prefixIcon:Icon(Icons.search),border:OutlineInputBorder()),
          )),
          Expanded(child:ListView.builder(itemCount:visible.length,itemBuilder:(context,i){
            final p=visible[i]; final id=p.id!;
            return CheckboxListTile(value:selected.contains(id),title:Text(p.displayName),
              secondary:const CircleAvatar(child:Icon(Icons.person_outline)),
              onChanged:(v)=>setDialogState((){ if(v??false){selected.add(id);}else{selected.remove(id);} }));
          })),
          Padding(padding:const EdgeInsets.all(14),child:Row(children:[
            Text('${selected.length} connected'),const Spacer(),
            TextButton(onPressed:()=>Navigator.pop(dc),child:const Text('Cancel')),const SizedBox(width:8),
            FilledButton.icon(onPressed:()=>Navigator.pop(dc,selected),icon:const Icon(Icons.check),label:const Text('Use People')),
          ])),
        ])));
      }),
    );
    if(result!=null&&mounted) setState(()=>_selectedPeople=result);
  }

  Future<void> _addImages() async {
    // ignore: deprecated_member_use
    final files = await FilePicker.pickFiles(type:FileType.image, allowMultiple:true);
    if (files.isEmpty) return;
    final root=await getApplicationDocumentsDirectory();
    final dir=Directory(path.join(root.path,'Heirloom Atlas','Antiques','Images'));
    await dir.create(recursive:true);
    final added=<String>[];
    for(final f in files){
      final src=f.path; if(src==null||src.isEmpty) continue;
      final dest=path.join(dir.path,'antique_${DateTime.now().microsecondsSinceEpoch}_${added.length}${path.extension(src)}');
      await File(src).copy(dest); added.add(dest);
    }
    if(mounted) setState(()=>_images.addAll(added));
  }

  Future<void> _addDocuments() async {
    // ignore: deprecated_member_use
    final files = await FilePicker.pickFiles(allowMultiple:true);
    if (files.isEmpty) return;
    final root=await getApplicationDocumentsDirectory();
    final dir=Directory(path.join(root.path,'Heirloom Atlas','Antiques','Documents'));
    await dir.create(recursive:true);
    final added=<String>[];
    for(final f in files){
      final src=f.path; if(src==null||src.isEmpty) continue;
      final dest=path.join(dir.path,'antique_${DateTime.now().microsecondsSinceEpoch}_${added.length}${path.extension(src)}');
      await File(src).copy(dest); added.add(dest);
    }
    if(mounted) setState(()=>_documents.addAll(added));
  }

  Future<void> _openFile(String filePath) async {
    if (!File(filePath).existsSync()) return;
    await Process.start('explorer.exe',[filePath],runInShell:true);
  }

  Future<void> _save() async {
    if(!_formKey.currentState!.validate()) return;
    setState(()=>_saving=true);
    try{
      final a=Antique(
        id:widget.antique?.id,title:_title.text.trim(),description:_description.text.trim(),
        year:_year.text.trim(),acquiredFrom:_acquiredFrom.text.trim(),
        purchasePrice:_money(_purchasePrice.text),estimatedValue:_money(_estimatedValue.text),
        notes:_notes.text.trim(),imagePaths:_images,condition:_condition,
        conditionNotes:_conditionNotes.text.trim(),provenance:_provenance.text.trim(),
        appraisalSource:_appraisalSource.text.trim(),valuationDate:_valuationDate.text.trim(),
        supportingDocumentPaths:_documents,
      );
      await _db.createDatabaseBackup(reason:_editing?'before_antique_update':'before_antique_add');
      final id=_editing ? (await _db.updateAntique(a), a.id!).$2 : await _db.insertAntique(a);
      await _db.replaceFamilyPeopleForItem(itemType:'antique',itemKey:id.toString(),personIds:_selectedPeople);
      if(mounted) Navigator.pop(context,true);
    }catch(e){
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Could not save antique: $e')));
    }finally{
      if(mounted) setState(()=>_saving=false);
    }
  }

  Future<void> _delete() async {
    final id=widget.antique?.id; if(id==null)return;
    final ok=await showDialog<bool>(context:context,builder:(dc)=>AlertDialog(
      title:const Text('Delete antique?'),content:const Text('This removes the record. Copied photos and supporting files remain in the Heirloom Atlas folders.'),
      actions:[TextButton(onPressed:()=>Navigator.pop(dc,false),child:const Text('Cancel')),
        FilledButton(onPressed:()=>Navigator.pop(dc,true),child:const Text('Delete'))]));
    if(ok!=true)return;
    await _db.createDatabaseBackup(reason:'before_antique_delete');
    await _db.deleteAntique(id);
    if(mounted)Navigator.pop(context,true);
  }

  Widget _heading(String title,String subtitle)=>Padding(
    padding:const EdgeInsets.only(bottom:10),
    child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text(title,style:Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight:FontWeight.w900)),
      const SizedBox(height:3),Text(subtitle,style:TextStyle(color:Theme.of(context).colorScheme.onSurfaceVariant)),
    ]));

  Widget _researchCard()=>Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(
    crossAxisAlignment:CrossAxisAlignment.start,children:[
      const Text('Research & Identification',style:TextStyle(fontWeight:FontWeight.w900,fontSize:18)),
      const SizedBox(height:6),const Text('Compare maker marks, examples, descriptions, and sold prices. Treat outside results as research clues, not confirmed facts.'),
      const SizedBox(height:12),TextField(controller:_research,onChanged:(_)=>setState((){}),
        onSubmitted:(_)=>_search('google'),decoration:InputDecoration(
          labelText:'Identification search',prefixIcon:const Icon(Icons.search),
          suffixIcon:_research.text.trim().isEmpty?null:IconButton(onPressed:()=>setState(()=>_research.clear()),icon:const Icon(Icons.close)),
          border:const OutlineInputBorder())),
      const SizedBox(height:8),TextButton.icon(onPressed:_refreshResearch,icon:const Icon(Icons.auto_fix_high_outlined),label:const Text('Build Search from Record')),
      Wrap(spacing:8,runSpacing:8,children:[
        FilledButton.icon(
          onPressed:_searchResearchOnline,
          icon:const Icon(Icons.travel_explore_outlined),
          label:const Text('Research Online'),
        ),
        OutlinedButton.icon(onPressed:()=>_search('google'),icon:const Icon(Icons.public),label:const Text('Google')),
        OutlinedButton.icon(onPressed:()=>_search('images'),icon:const Icon(Icons.image_search_outlined),label:const Text('Google Images')),
        OutlinedButton.icon(onPressed:()=>_search('ebay'),icon:const Icon(Icons.shopping_bag_outlined),label:const Text('eBay')),
        OutlinedButton.icon(onPressed:()=>_search('sold'),icon:const Icon(Icons.price_check_outlined),label:const Text('eBay Sold')),
        OutlinedButton.icon(onPressed:()=>_search('etsy'),icon:const Icon(Icons.storefront_outlined),label:const Text('Etsy')),
        OutlinedButton.icon(onPressed:()=>_search('auction'),icon:const Icon(Icons.gavel_outlined),label:const Text('Auction / Reference Sites')),
      ])
    ])));

  Widget _photos()=>Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Row(children:[Expanded(child:Text('Photos',style:Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight:FontWeight.w800))),
      FilledButton.tonalIcon(onPressed:_addImages,icon:const Icon(Icons.add_photo_alternate_outlined),label:const Text('Add Photos'))]),
    const SizedBox(height:10),
    if(_images.isEmpty) const Text('No photos added yet')
    else SizedBox(height:180,child:ListView.separated(scrollDirection:Axis.horizontal,itemCount:_images.length,
      separatorBuilder:(_,_)=>const SizedBox(width:10),itemBuilder:(context,i)=>SizedBox(width:230,child:Card(
        clipBehavior:Clip.antiAlias,child:Stack(fit:StackFit.expand,children:[
          File(_images[i]).existsSync()?Image.file(File(_images[i]),fit:BoxFit.contain):const Icon(Icons.broken_image_outlined),
          Positioned(top:6,right:6,child:IconButton.filledTonal(onPressed:()=>setState(()=>_images.removeAt(i)),icon:const Icon(Icons.close)))
        ]))))),
  ]);

  Widget _familyCard() {
    final selected=_familyPeople.where((p)=>p.id!=null&&_selectedPeople.contains(p.id)).toList();
    return Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(children:[const Icon(Icons.account_tree_outlined),const SizedBox(width:8),
        const Expanded(child:Text('Family Connections & Provenance',style:TextStyle(fontWeight:FontWeight.w800,fontSize:17))),
        OutlinedButton.icon(onPressed:_chooseFamily,icon:const Icon(Icons.edit_outlined),label:Text(selected.isEmpty?'Choose People':'Manage'))]),
      const SizedBox(height:8),const Text('Connect people who owned, used, made, inherited, or are part of this antique’s story.'),
      if(selected.isNotEmpty)...[const SizedBox(height:10),Wrap(spacing:8,children:selected.map((p)=>ActionChip(
        avatar:const Icon(Icons.person_outline,size:17),label:Text(p.displayName),onPressed:()async{
          await Navigator.push(context,MaterialPageRoute(builder:(_)=>FamilyPersonScreen(person:p))); await _loadFamily();
        })).toList())]
    ])));
  }

  Widget _documentsCard()=>Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(
    crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(children:[const Expanded(child:Text('Supporting Materials',style:TextStyle(fontWeight:FontWeight.w900,fontSize:18))),
        FilledButton.tonalIcon(onPressed:_addDocuments,icon:const Icon(Icons.attach_file),label:const Text('Add Files'))]),
      const SizedBox(height:6),const Text('Receipts, appraisals, certificates, research PDFs, provenance records, and other supporting documents.'),
      if(_documents.isEmpty)...[const SizedBox(height:10),const Text('No supporting materials attached.')]
      else ..._documents.asMap().entries.map((e)=>ListTile(
        dense:true,leading:const Icon(Icons.description_outlined),title:Text(path.basename(e.value)),
        onTap:()=>_openFile(e.value),trailing:IconButton(tooltip:'Remove from record',onPressed:()=>setState(()=>_documents.removeAt(e.key)),icon:const Icon(Icons.close))))
    ])));

  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(_editing?'Edit Antique':'Add Antique'),actions:[
      if(_editing)IconButton(tooltip:'Delete Antique',onPressed:_delete,icon:const Icon(Icons.delete_outline))
    ]),
    body:SingleChildScrollView(padding:const EdgeInsets.fromLTRB(24,24,24,36),child:Center(child:ConstrainedBox(
      constraints:const BoxConstraints(maxWidth:1000),child:Form(key:_formKey,child:Column(
        crossAxisAlignment:CrossAxisAlignment.start,children:[
          _photos(),const SizedBox(height:20),_researchCard(),const SizedBox(height:24),
          _heading('Identification & Description','Record what the object is and the details that distinguish it.'),
          TextFormField(controller:_title,decoration:const InputDecoration(labelText:'Title / Identification',border:OutlineInputBorder())),
          const SizedBox(height:14),TextFormField(controller:_description,maxLines:4,decoration:const InputDecoration(
            labelText:'Description / Identifying Details',hintText:'Maker marks, material, color, pattern, dimensions...',border:OutlineInputBorder())),
          const SizedBox(height:14),Row(children:[
            Expanded(child:TextFormField(controller:_year,decoration:const InputDecoration(labelText:'Year / Date',border:OutlineInputBorder()))),
            const SizedBox(width:14),Expanded(child:TextFormField(controller:_acquiredFrom,decoration:const InputDecoration(labelText:'Acquired From',border:OutlineInputBorder())))
          ]),
          const SizedBox(height:20),_heading('Condition','Keep condition separate from general description so it can be reviewed over time.'),
          DropdownButtonFormField<String>(initialValue:_condition.isEmpty?null:_condition,
            items:const ['Excellent','Very Good','Good','Fair','Poor','Unknown'].map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),
            onChanged:(v)=>setState(()=>_condition=v??''),decoration:const InputDecoration(labelText:'Condition',border:OutlineInputBorder())),
          const SizedBox(height:14),TextFormField(controller:_conditionNotes,maxLines:3,decoration:const InputDecoration(
            labelText:'Condition Notes',hintText:'Wear, cracks, repairs, missing pieces, restoration...',border:OutlineInputBorder())),
          const SizedBox(height:20),_heading('Provenance & Family History','Preserve how the object moved through the family and why it matters.'),
          TextFormField(controller:_provenance,maxLines:4,decoration:const InputDecoration(
            labelText:'Ownership / Provenance History',hintText:'Who owned it, how it passed through the family, where it came from...',border:OutlineInputBorder())),
          const SizedBox(height:14),_familyCard(),
          const SizedBox(height:24),_heading('Value & Appraisal','Track the current estimate and where that estimate came from.'),
          Row(children:[
            Expanded(child:TextFormField(controller:_purchasePrice,keyboardType:const TextInputType.numberWithOptions(decimal:true),
              validator:(v){final t=v?.trim()??'';return t.isNotEmpty&&_money(t)==null?'Enter a valid amount':null;},
              decoration:const InputDecoration(labelText:'Purchase Price',prefixText:r'$',border:OutlineInputBorder()))),
            const SizedBox(width:14),
            Expanded(child:TextFormField(controller:_estimatedValue,keyboardType:const TextInputType.numberWithOptions(decimal:true),
              validator:(v){final t=v?.trim()??'';return t.isNotEmpty&&_money(t)==null?'Enter a valid amount':null;},
              decoration:const InputDecoration(labelText:'Estimated / Appraised Value',prefixText:r'$',border:OutlineInputBorder())))
          ]),
          const SizedBox(height:14),Row(children:[
            Expanded(child:TextFormField(controller:_appraisalSource,decoration:const InputDecoration(
              labelText:'Value / Appraisal Source',hintText:'Appraiser, eBay sold comps, auction house...',border:OutlineInputBorder()))),
            const SizedBox(width:14),Expanded(child:TextFormField(controller:_valuationDate,decoration:const InputDecoration(
              labelText:'Valuation Date',hintText:'2026-08-30 or Aug 2026',border:OutlineInputBorder())))
          ]),
          const SizedBox(height:18),_documentsCard(),const SizedBox(height:20),
          TextFormField(controller:_notes,maxLines:6,decoration:const InputDecoration(
            labelText:'History / Research Notes',hintText:'Family story, research findings, comparable sales, uncertainties...',border:OutlineInputBorder())),
          const SizedBox(height:24),Align(alignment:Alignment.centerRight,child:FilledButton.icon(
            onPressed:_saving?null:_save,icon:_saving?const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.save_outlined),
            label:Text(_saving?'Saving...':'Save Antique')))
        ]))))),
  );
}
