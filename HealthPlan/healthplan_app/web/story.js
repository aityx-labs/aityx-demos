// Who's on the plan, read from a story the visitor wrote: the names it gives, the one writing ("I", "me"),
// and the people it names only by how they're related ("my wife", "our two kids"), with the ages it writes.
// aityx's questions are about people it is given, so the page finds them first; aityx then reads each one's year.
// No model, no network: the story's own words.
(function(){
  const NUM={one:1,two:2,three:3,four:4,five:5,six:6};
  // A name is a capitalized word that does something in the story: followed by a verb about them.
  const VERB="is|isn['’]t|are|has|hasn['’]t|have|had|takes|took|needs|need|sees|saw|uses|used|gets|got|will|won['’]t|was|were|does|doesn['’]t|did|just|only|also|still|might|may|should|could|can|can['’]t|must|goes|went|broke|plays|starts|started|turns|turned|plans|wants|expects|lives|keeps|deals|struggles|suffers|recently|probably|rarely|never|often|usually|always|hurt|tore|sprained|fell|stays|requires|wears|would|already|seems|feels|became|developed|visits|sees|gave|wants|hopes|['’]s|['’]ll|['’]d";
  // Capitalized words that aren't people, even before such a verb.
  const NOT=new Set(("I We Our My Me He She They His Her Their It Its The A An And But Or So Then Also Plus Just Only Both All Everyone Everybody Nobody Nothing Otherwise "+
    "Maybe Since After Before Until During In On At For From With Without Of To By Next This That These Those Last Every Each Most Some No Not Yes Hi Hello Thanks Please "+
    "Well Oh Lately Recently Currently Still Already Soon Later Once Twice Hopefully Probably Unfortunately Luckily Also There Here What When Where Why How Who Which "+
    "Dr Doctor Mr Mrs Ms Nurse January February March April June July August September October November December Jan Feb Mar Apr Jun Jul Aug Sep Sept Oct Nov Dec "+
    "Monday Tuesday Wednesday Thursday Friday Saturday Sunday Christmas Easter Thanksgiving Type Covid Medicare Medicaid Bronze Silver Gold Crohn Lyme Down Parkinson "+
    "Alzheimer Hashimoto Graves Addison Cushing Hodgkin Bell Tourette Asperger Huntington Celiac Botox Ozempic Insulin Physical Therapy Year New One Two Three Four Five").split(" "));
  const NAME="[A-Z][a-z]+(?:-[A-Z][a-z]+)?";
  const KIDS="son|daughter|kid|child|toddler|teen|teenager|boy|girl|stepson|stepdaughter";
  const ADULTS="wife|husband|partner|spouse|fianc[ée]e?|mom|mother|dad|father";
  const GROUPS="sons|daughters|kids|children|boys|girls|twins|teens";

  const esc=s=>s.replace(/[.*+?^${}()|[\]\\]/g,"\\$&");
  const ageOk=n=>n>=0&&n<=110;
  function ageOf(text,name){
    const N=esc(name), tries=[
      new RegExp(`\\b${N}\\s*\\((?:age\\s*|aged\\s*)?(\\d{1,3})\\)`),
      new RegExp(`\\b${N},\\s*(\\d{1,3})\\s*(?:,|\\.|\\b(?:and|has|is|needs|takes|sees|will)\\b)`),
      new RegExp(`\\b${N}\\s+(?:is|turns|just turned|will be)\\s+(\\d{1,3})\\b(?!\\s*(?:weeks|months|days|%))`),
      new RegExp(`\\b${N},?\\s+(?:who['’]s|who is|aged|age)\\s+(\\d{1,3})\\b(?!\\s*(?:weeks|months|days))`),
      new RegExp(`\\b(\\d{1,3})[- ](?:year|yr)[- ]old\\s+(?:[a-z]+\\s+){0,2}${N}\\b`)];
    for(const re of tries){ const m=re.exec(text); if(m&&ageOk(+m[1])) return +m[1]; }
    return null;
  }

  /**
   * The people a story names, in the order it names them: [{name, age, kid, said}], `age` null when the story
   * doesn't give one, `kid` whether the words say it's a child, `said` how it was found (name, writer, relation).
   * `known` is the list on screen: someone already there keeps their age; the writer takes the place of the
   * one adult on the list the story doesn't name ("I take a thyroid pill" is Dana's).
   */
  function peopleIn(story,known){
    const text=String(story||"").replace(/\s+/g," ").trim();
    known=known||[];
    const out=[], has=n=>out.some(p=>p.name.toLowerCase()===n.toLowerCase());
    const add=(name,age,kid,said)=>{ if(!name||has(name)) return; out.push({name,age,kid,said}); };

    // Named people: "Leo has asthma", "Zoe's tonsils", "Leo and Ava need checkups", "my son Leo", "Leo (9)".
    const named=[];
    const put=n=>{ if(!NOT.has(n)&&!named.includes(n)) named.push(n); };
    const notTitle=(i)=>!/\b(?:Dr|Doctor|Mr|Mrs|Ms|Nurse|Dr\.)\.?\s*$/.test(text.slice(Math.max(0,i-8),i));
    const listed=new RegExp(`\\b(${NAME}(?:\\s*,\\s*${NAME})*(?:,?\\s+and\\s+${NAME})?)(?=\\s*(?:\\(\\d|,\\s*\\d{1,2}\\b|(?:\\s+(?:${VERB})\\b)|['’]s\\b|['’]ll\\b))`,"g");
    for(const m of text.matchAll(listed)) if(notTitle(m.index)) m[1].split(/\s*,\s*|,?\s+and\s+/).forEach(put);
    const related=new RegExp(`\\b(?:[Mm]y|[Oo]ur|[Hh]is|[Hh]er|[Tt]heir)\\s+(?:\\d{1,2}[- ](?:year|yr)[- ]old\\s+)?(?:${KIDS}|${ADULTS}|${GROUPS})\\s*,?\\s+(${NAME}(?:\\s+and\\s+${NAME})?)`,"g");
    for(const m of text.matchAll(related)) m[1].split(/\s+and\s+/).forEach(put);
    const isKid=n=>new RegExp(`\\b(?:${KIDS}|${GROUPS})\\s*,?\\s+(?:${NAME}\\s+and\\s+)?${esc(n)}\\b|\\b${esc(n)}\\b[^.]{0,30}\\b(?:pediatrician|school|daycare|preschool|kindergarten|grade)\\b`).test(text);

    // The one writing: "I", "I'm 27", "me", "my".
    const writer=/(?:^|[^A-Za-z])I(?:['’](?:m|ve|d|ll))?\b/.test(text)||/\b(?:me|my|myself)\b/i.test(text);
    const unnamedKnown=known.filter(k=>k.age>=18&&!named.some(n=>n.toLowerCase()===k.name.toLowerCase()));
    if(writer){
      const m=/\bI(?:['’]m| am)\s+(?:a\s+)?(\d{1,3})\b/.exec(text)||/\bI(?:['’]m| am)\s+(?:a\s+)?(\d{1,3})[- ]year[- ]old\b/.exec(text);
      const k=unnamedKnown.length===1?unnamedKnown[0]:null;
      add(k?k.name:"You",m&&ageOk(+m[1])?+m[1]:k?k.age:null,false,"writer");
    }
    for(const n of named) add(n,ageOf(text,n),isKid(n),"name");

    // People named by how they're related, without a name: "my wife is pregnant", "our two kids", "the kids".
    const bare=new RegExp(`\\b([Mm]y|[Oo]ur|[Tt]he)\\s+(?:(\\d|${Object.keys(NUM).join("|")}|${Object.keys(NUM).map(w=>w[0].toUpperCase()+w.slice(1)).join("|")})\\s+)?(?:(\\d{1,2})[- ](?:year|yr)[- ]old\\s+)?(${KIDS}|${ADULTS}|${GROUPS})\\b(?!\\s*,?\\s+${NAME})`,"g");
    for(const m of text.matchAll(bare)){
      const who=m[4].toLowerCase(), group=new RegExp(`^(?:${GROUPS})$`).test(who);
      if(m[1].toLowerCase()==="the"&&!group) continue; // "the doctor's son": not on the plan
      if(group){
        const n=Math.min(6,m[2]?(NUM[m[2].toLowerCase()]||+m[2]):who==="twins"?2:2);
        const one=who==="twins"?"Twin":"Kid";
        if(out.filter(p=>p.kid).length>=n) continue; // the kids are named already
        for(let i=1;i<=n;i++) add(`${one} ${i}`,m[3]?+m[3]:null,true,"relation");
      } else {
        const kid=new RegExp(`^(?:${KIDS})$`).test(who);
        add(`Your ${who}`,m[3]?+m[3]:null,kid,"relation");
      }
    }
    // Someone already on the list keeps the age the story doesn't give.
    out.forEach(p=>{ if(p.age==null){ const k=known.find(x=>x.name.toLowerCase()===p.name.toLowerCase()); if(k) p.age=k.age; } });
    return out;
  }
  const api={peopleIn};
  if(typeof module!=="undefined"&&module.exports) module.exports=api; else window.Story=api;
})();
