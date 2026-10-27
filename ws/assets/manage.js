const el=(id)=>document.getElementById(id);
const lang={current:'ar'};
const labels={
 ar:{title:'طلبات الجملة',subtitle:'مراجعة منظمة للطلبات دون المساس بالدفع أو المخزون.',auth:'دخول الموظفين',authHelp:'هذه المساحة تتطلب تصريح بيع الجملة في الفرع المحدد.',login:'دخول',logout:'خروج',store:'المتجر',branch:'الفرع',status:'الحالة',count:'طلب',refresh:'تحديث',pending:'بانتظار المراجعة',accepted:'جاهز للمعالجة',rejected:'مرفوض',cancelled:'ملغي من العميل',policy:'قبول الطلب لا يعتبر عملية بيع أو قبضاً أو حجزاً للمخزون؛ يجب إكمال البيع عبر نقطة البيع المصرح بها.',empty:'لا توجد طلبات ضمن هذا الاختيار.',unauthorized:'لا تملك صلاحيات فروع الجملة. اطلب من مسؤول النظام مراجعة الصلاحيات.',unavailable:'تعذر تحميل الطلبات. حاول مرة أخرى.',accept:'قبول للمراجعة النهائية',reject:'رفض الطلب',quantity:'العبوات',total:'الإجمالي',notes:'ملاحظات المراجعة (اختياري)',submit:'تأكيد القرار',processing:'جارٍ التنفيذ...',loginFailed:'بيانات الدخول غير صحيحة أو الخدمة غير متاحة.',ready:'جاهز لمراجعة طلبات الفرع',review:'قرار المراجعة',error:'تعذر حفظ القرار. تحقق من الحالة والصلاحيات.',success:'تم تسجيل قرار المراجعة',customer:'حساب العميل'},
 en:{title:'Wholesale requests',subtitle:'A focused review workspace, without changing payments or inventory.',auth:'Staff sign-in',authHelp:'This workspace requires wholesale selling permission for an authorized branch.',login:'Sign in',logout:'Sign out',store:'Storefront',branch:'Branch',status:'Status',count:'requests',refresh:'Refresh',pending:'Pending review',accepted:'Ready to process',rejected:'Rejected',cancelled:'Cancelled by customer',policy:'Accepting a request does not create a sale, collect payment, or reserve inventory. Complete sales via authorized POS.',empty:'No requests match this filter.',unauthorized:'You have no authorized wholesale branches. Ask your administrator to check permissions.',unavailable:'Could not load requests. Try again.',accept:'Accept for processing',reject:'Reject',quantity:'Packs',total:'Estimated amount',notes:'Review notes (optional)',submit:'Confirm decision',processing:'Processing...',loginFailed:'Sign in failed or service unavailable.',ready:'Reviewing branch requests',review:'Review decision',error:'Could not save review. Check status and permissions.',success:'Review decision recorded',customer:'Buyer account'}
};
const t=k=>labels[lang.current][k]||k;
const safe=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const money=(minor,currency)=>{try{return new Intl.NumberFormat(lang.current==='ar'?'ar':'en',{style:'currency',currency:currency||'QAR'}).format((minor||0)/100)}catch{return ((minor||0)/100).toFixed(2)+' '+(currency||'QAR')}};
const state={api:null,user:null,branches:[],requests:[],branch:'',status:'pending_review',review:null};
let timer;
function toast(text){el('managerToast').textContent=text;el('managerToast').hidden=false;clearTimeout(timer);timer=setTimeout(()=>el('managerToast').hidden=true,3900)}
function setText(id,text){el(id).textContent=text}
function locale(){
 document.documentElement.dir=lang.current==='ar'?'rtl':'ltr';document.documentElement.lang=lang.current;
 setText('managerTitle',t('title'));setText('managerSubtitle',t('subtitle'));setText('authHeading',t('auth'));setText('authHelp',t('authHelp'));
 setText('managerLogin',t('login'));setText('logoutBtn',t('logout'));setText('publicLink',t('store'));setText('branchLabel',t('branch'));setText('statusLabel',t('status'));
 setText('refreshManager',t('refresh'));setText('requestCountLabel',t('count'));setText('staffPolicy',t('policy'));setText('reviewTitle',t('review'));
 setText('reviewNoteLabel',t('notes'));setText('confirmReview',t('submit'));setText('langBtn',lang.current==='ar'?'EN':'عربي');
 const select=el('managerStatus');const values=['pending_review','accepted_for_processing','rejected','cancelled_by_customer'];
 const keys=['pending','accepted','rejected','cancelled'];values.forEach((v,i)=>{const opt=select.querySelector('[value="'+v+'"]');if(opt)opt.textContent=t(keys[i])});
 const notes=el('reviewWarning');notes.textContent=t('policy');
 paintBranches();paintRequests();
}
function paintBranches(){
 const select=el('managerBranch');select.replaceChildren();
 state.branches.forEach(branch=>{const opt=document.createElement('option');opt.value=branch.id;opt.textContent=lang.current==='ar'?(branch.nameAr||branch.nameEn):(branch.nameEn||branch.nameAr);select.append(opt)});
 if(state.branches.some(b=>b.id===state.branch))select.value=state.branch;
}
function paintRequests(){
 const box=el('managerQueue');box.replaceChildren();setText('requestCount',String(state.requests.length));
 if(!state.requests.length){const empty=document.createElement('div');empty.className='empty-state';const strong=document.createElement('strong');strong.textContent=t('empty');empty.append(strong);box.append(empty);return;}
 state.requests.forEach(record=>{
  const card=document.createElement('article');card.className='manager-request';
  const head=document.createElement('div');head.className='manager-card-top';
  head.innerHTML='<div><strong>#'+safe(record.orderNumber||record.id.slice(0,10))+'</strong><small>'+safe(t('customer'))+': '+safe(record.ownerUid||'')+'</small></div><span class="manager-card-tag">'+safe(record.status||'pending_review')+'</span>';
  const items=document.createElement('div');items.className='manager-items';
  (record.items||[]).forEach(line=>{
    const row=document.createElement('div');row.className='manager-item-row';
    const label=lang.current==='ar'?(line.nameAr||line.nameEn):(line.nameEn||line.nameAr);
    row.innerHTML='<span>'+safe(label)+' · '+safe(line.groupId)+'</span><span>'+safe(String(line.groupQuantity))+' '+safe(t('quantity'))+' · '+safe(money(line.lineTotalMinor,record.currency))+'</span>';
    items.append(row);
  });
  const foot=document.createElement('div');foot.className='manager-card-footer';
  const total=document.createElement('strong');total.textContent=money(record.totalMinor,record.currency);foot.append(total);
  if(record.status==='pending_review'){
   const actions=document.createElement('div');actions.className='manager-card-buttons';
   for(const decision of ['reject','accept']){
    const b=document.createElement('button');b.type='button';b.dataset.decision=decision;b.dataset.id=record.id;b.textContent=t(decision);actions.append(b);
   }
   foot.append(actions);
  }
  card.append(head,items,foot);box.append(card);
 });
}
async function connect(){
 const response=await fetch('/ws/api/config',{cache:'no-store'});if(!response.ok)throw new Error('Missing configuration');
 const cfg=await response.json();if(!cfg.appCheckSiteKey)throw new Error('Missing App Check site key');
 const [{initializeApp},{getAuth,onAuthStateChanged,signInWithEmailAndPassword,signOut},{getFunctions,httpsCallable},{initializeAppCheck,ReCaptchaV3Provider}]
   = await Promise.all([
    import('https://www.gstatic.com/firebasejs/11.10.0/firebase-app.js'),
    import('https://www.gstatic.com/firebasejs/11.10.0/firebase-auth.js'),
    import('https://www.gstatic.com/firebasejs/11.10.0/firebase-functions.js'),
    import('https://www.gstatic.com/firebasejs/11.10.0/firebase-app-check.js')]);
 const app=initializeApp(cfg.firebase,'pure-pets-wholesale-operations');
 initializeAppCheck(app,{provider:new ReCaptchaV3Provider(cfg.appCheckSiteKey),isTokenAutoRefreshEnabled:true});
 const auth=getAuth(app),functions=getFunctions(app,cfg.region||'us-central1');
 state.api={auth,signInWithEmailAndPassword,signOut,call:async(name,data={})=>(await httpsCallable(functions,name,{timeout:25000})(data)).data};
 onAuthStateChanged(auth,async(user)=>{
  state.user=user||null;state.branches=[];state.requests=[];state.branch='';
  el('logoutBtn').hidden=!user;el('managerAuth').hidden=!!user;el('managerWorkspace').hidden=!user;
  if(user)await loadBranches();
 });
}
async function loadBranches(){
 try{
  const result=await state.api.call('listWholesaleStaffBranches');
  state.branches=Array.isArray(result.branches)?result.branches:[];
  if(!state.branches.length){setText('managerMessage',t('unauthorized'));paintBranches();paintRequests();return;}
  state.branch=state.branches[0].id;paintBranches();await reload();
 }catch(err){setText('managerMessage',t('unavailable'));console.warn('Workspace access denied',err?.code)}
}
async function reload(){
 if(!state.api||!state.user||!state.branch)return;
 setText('managerMessage',t('processing'));el('refreshManager').disabled=true;
 try{
   const result=await state.api.call('listWholesaleStaffRequests',{branchId:state.branch,statuses:[state.status],limit:50});
   state.requests=Array.isArray(result.items)?result.items:[];setText('managerMessage',t('ready'));
 }catch(err){state.requests=[];setText('managerMessage',t('unavailable'));console.warn('Wholesale queue failed',err?.code)}
 finally{el('refreshManager').disabled=false;paintRequests();}
}
el('managerAuthForm').addEventListener('submit',async e=>{
 e.preventDefault();const btn=el('managerLogin');btn.disabled=true;
 try{await state.api.signInWithEmailAndPassword(state.api.auth,el('managerEmail').value.trim(),el('managerPassword').value);el('managerPassword').value='';}
 catch(error){toast(t('loginFailed'));console.warn('Sign in',error?.code);}
 finally{btn.disabled=false;}
});
el('logoutBtn').addEventListener('click',async()=>{if(state.api)await state.api.signOut(state.api.auth)});
el('langBtn').addEventListener('click',()=>{lang.current=lang.current==='ar'?'en':'ar';locale()});
el('managerBranch').addEventListener('change',e=>{state.branch=e.target.value;reload()});
el('managerStatus').addEventListener('change',e=>{state.status=e.target.value;reload()});
el('refreshManager').addEventListener('click',reload);
el('managerQueue').addEventListener('click',e=>{
 const button=e.target.closest('[data-decision]');if(!button)return;
 const rec=state.requests.find(x=>x.id===button.dataset.id);if(!rec)return;
 state.review={id:rec.id,branchId:rec.branchId,decision:button.dataset.decision};
 el('reviewSummary').textContent='#'+(rec.orderNumber||rec.id.slice(0,10))+' · '+money(rec.totalMinor,rec.currency);
 el('reviewNote').value='';el('reviewDialog').showModal();
});
el('closeReview').addEventListener('click',()=>el('reviewDialog').close());
el('confirmReview').addEventListener('click',async()=>{
 const r=state.review;if(!r)return;
 const btn=el('confirmReview');btn.disabled=true;btn.textContent=t('processing');
 try{
  await state.api.call('reviewWholesaleStaffRequest',{requestId:r.id,branchId:r.branchId,decision:r.decision,note:el('reviewNote').value});
  el('reviewDialog').close();toast(t('success'));await reload();
 }catch(e){toast(t('error'));console.warn('Review failed',e?.code);}
 finally{btn.disabled=false;btn.textContent=t('submit');}
});
locale();connect().catch(()=>{setText('managerMessage',t('unavailable'));toast(t('unavailable'))});
