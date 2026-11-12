// Holiday Split: the page's logic, from the original single-file prototype.
// aityx.js holds the key and makes the calls; reader.js runs the trip reader,
// a small LLM on the device (transformers.js in a Web Worker).
import "./style.css";
import recordings from "./recordings.json";
import * as aityx from "./aityx.js";
import * as reader from "./reader.js";

const SAMPLES = {
  cabin:{trip:"cabin",kind:"all",result:"Leo comes for 2 nights. Rose and Ana skip the drinks.",label:"Christmas at the cabin",start:"2026-12-23",host:"sam",
    text:"Christmas at a cabin in the Smokies, 5 nights from Dec 23, $1,850. Sam booked it and paid. Jan and Mo are bringing the kids, Lily (4) and Max (12). Grandma Rose is coming too, she doesn't drink. Leo only makes it for the last 2 nights. Mo did the grocery run, $420. Ana doesn't drink. Sam also got the wine and beer, $180.",
    people:[
      {id:"sam",name:"Sam",age:null,nights:5,drinks:true},
      {id:"jan",name:"Jan",age:null,nights:5,drinks:true},
      {id:"mo",name:"Mo",age:null,nights:5,drinks:true},
      {id:"lily",name:"Lily",age:4,nights:5,drinks:false,guardians:["jan","mo"]},
      {id:"max",name:"Max",age:12,nights:5,drinks:false,guardians:["jan","mo"]},
      {id:"rose",name:"Grandma Rose",age:null,nights:5,drinks:false},
      {id:"leo",name:"Leo",age:null,nights:2,drinks:true},
      {id:"ana",name:"Ana",age:null,nights:5,drinks:false}],
    expenses:[{kind:"lodging",what:"Cabin",amount:1850,by:"sam"},{kind:"groceries",what:"Groceries",amount:420,by:"mo"},{kind:"drinks",what:"Wine and beer",amount:180,by:"sam"}],
    exempt:[], nudge:"Try it: tap Grandma Rose."},
  ski:{trip:"ski",kind:"all",result:"Tom and Lu leave a night early and pay for 3 nights.",label:"New Year's with friends",start:"2026-12-29",host:"priya",
    text:"Lake house for New Year's, 4 nights from Dec 29, $2,400. Priya booked it. It's Priya, Dev, Maya, Tom, Lu and Chris. Tom and Lu leave on the 1st, a night early. Dev and Maya don't drink. Maya paid for groceries, $360. Tom got the champagne and drinks, $240.",
    people:[
      {id:"priya",name:"Priya",age:null,nights:4,drinks:true},
      {id:"dev",name:"Dev",age:null,nights:4,drinks:false},
      {id:"maya",name:"Maya",age:null,nights:4,drinks:false},
      {id:"tom",name:"Tom",age:null,nights:3,drinks:true},
      {id:"lu",name:"Lu",age:null,nights:3,drinks:true},
      {id:"chris",name:"Chris",age:null,nights:4,drinks:true}],
    expenses:[{kind:"lodging",what:"Lake house",amount:2400,by:"priya"},{kind:"groceries",what:"Groceries",amount:360,by:"maya"},{kind:"drinks",what:"Champagne and drinks",amount:240,by:"tom"}],
    exempt:[], nudge:""},
  thanks:{trip:"thanks",kind:"out",result:"Mom hosts and doesn't pay. The others cover her share.",label:"Thanksgiving at Mom's",start:"2026-11-26",host:"mom",
    text:"Thanksgiving at Mom's on Nov 26. Mom bought the turkey and groceries, $310, and says she's not paying a cent, it's her house. Carlos brought wine, $95. Bea made the pies, $48, and doesn't drink. Bea's partner Sam is coming. Uncle Joe brings his kids, Nina (3), Theo (8) and Ava (15).",
    people:[
      {id:"mom",name:"Mom",age:null,nights:1,drinks:true},
      {id:"carlos",name:"Carlos",age:null,nights:1,drinks:true},
      {id:"bea",name:"Bea",age:null,nights:1,drinks:false},
      {id:"sam",name:"Sam",age:null,nights:1,drinks:true},
      {id:"joe",name:"Uncle Joe",age:null,nights:1,drinks:true},
      {id:"nina",name:"Nina",age:3,nights:1,drinks:false,guardians:["joe"]},
      {id:"theo",name:"Theo",age:8,nights:1,drinks:false,guardians:["joe"]},
      {id:"ava",name:"Ava",age:15,nights:1,drinks:false,guardians:["joe"]}],
    expenses:[{kind:"groceries",what:"Turkey and groceries",amount:310,by:"mom"},{kind:"drinks",what:"Wine",amount:95,by:"carlos"},{kind:"groceries",what:"Pies",amount:48,by:"bea"}],
    exempt:["mom"], nudge:"Mom said she's not paying, so we already marked her."},
  cabin_out:{trip:"cabin",kind:"out",result:"Grandpa Walt is the group's treat. The others cover him.",label:"Christmas in Vermont",start:"2026-12-22",host:"nora",
    text:"Christmas at a farmhouse in Vermont, 4 nights from Dec 22, $1,600. Nora booked it and paid. Grandpa Walt is our treat this year, he doesn't pay a thing. Eli and Rae bring their son Finn (9). Rae doesn't drink. Eli did the groceries, $380. Nora got the wine and eggnog, $150.",
    people:[
      {id:"nora",name:"Nora",age:null,nights:4,drinks:true},
      {id:"walt",name:"Grandpa Walt",age:null,nights:4,drinks:true},
      {id:"eli",name:"Eli",age:null,nights:4,drinks:true},
      {id:"rae",name:"Rae",age:null,nights:4,drinks:false},
      {id:"finn",name:"Finn",age:9,nights:4,drinks:false,guardians:["eli","rae"]}],
    expenses:[{kind:"lodging",what:"Farmhouse",amount:1600,by:"nora"},{kind:"groceries",what:"Groceries",amount:380,by:"eli"},{kind:"drinks",what:"Wine and eggnog",amount:150,by:"nora"}],
    exempt:["walt"], nudge:"Grandpa Walt is the group's treat, so he's marked as not paying."},
  cabin_lake:{trip:"cabin",kind:"all",result:"Mia, 7, pays half. Ben skips the drinks.",label:"Christmas by the lake",start:"2026-12-24",host:"dana",
    text:"Christmas at a lake cabin, 3 nights from Dec 24, $1,200. Dana booked it and paid. Kai, Jo and Ben are coming, plus Jo's daughter Mia (7). Ben doesn't drink. Kai bought groceries, $300. Jo got the drinks, $120.",
    people:[
      {id:"dana",name:"Dana",age:null,nights:3,drinks:true},
      {id:"kai",name:"Kai",age:null,nights:3,drinks:true},
      {id:"jo",name:"Jo",age:null,nights:3,drinks:true},
      {id:"ben",name:"Ben",age:null,nights:3,drinks:false},
      {id:"mia",name:"Mia",age:7,nights:3,drinks:false,guardians:["jo"]}],
    expenses:[{kind:"lodging",what:"Lake cabin",amount:1200,by:"dana"},{kind:"groceries",what:"Groceries",amount:300,by:"kai"},{kind:"drinks",what:"Drinks",amount:120,by:"jo"}],
    exempt:[], nudge:"Try it: tap Dana to treat her this year."},
  ski_out:{trip:"ski",kind:"out",result:"It's Iris's birthday. The others cover her share.",label:"New Year's at the beach",start:"2026-12-30",host:"rafa",
    text:"Beach house for New Year's, 3 nights from Dec 30, $1,950. Rafa booked it. It's Rafa, Iris, Noah, Zoe and Sam. It's Iris's birthday, so the rest of us are covering her this time. Noah doesn't drink. Zoe got the groceries, $270. Sam bought the champagne, $160.",
    people:[
      {id:"rafa",name:"Rafa",age:null,nights:3,drinks:true},
      {id:"iris",name:"Iris",age:null,nights:3,drinks:true},
      {id:"noah",name:"Noah",age:null,nights:3,drinks:false},
      {id:"zoe",name:"Zoe",age:null,nights:3,drinks:true},
      {id:"sam",name:"Sam",age:null,nights:3,drinks:true}],
    expenses:[{kind:"lodging",what:"Beach house",amount:1950,by:"rafa"},{kind:"groceries",what:"Groceries",amount:270,by:"zoe"},{kind:"drinks",what:"Champagne",amount:160,by:"sam"}],
    exempt:["iris"], nudge:"It's Iris's birthday, so she's marked as not paying."},
  ski_mtn:{trip:"ski",kind:"all",result:"Ken and Ari leave early. Ari skips the drinks.",label:"New Year's in the mountains",start:"2026-12-28",host:"jules",
    text:"Mountain cabin for New Year's, 4 nights from Dec 28, $2,000. Jules booked it. It's Jules, Ken, Ari, Bo and Lee. Ken and Ari leave a night early. Ari doesn't drink. Bo got the groceries, $320. Ken got the drinks, $200.",
    people:[
      {id:"jules",name:"Jules",age:null,nights:4,drinks:true},
      {id:"ken",name:"Ken",age:null,nights:3,drinks:true},
      {id:"ari",name:"Ari",age:null,nights:3,drinks:false},
      {id:"bo",name:"Bo",age:null,nights:4,drinks:true},
      {id:"lee",name:"Lee",age:null,nights:4,drinks:true}],
    expenses:[{kind:"lodging",what:"Mountain cabin",amount:2000,by:"jules"},{kind:"groceries",what:"Groceries",amount:320,by:"bo"},{kind:"drinks",what:"Drinks",amount:200,by:"ken"}],
    exempt:[], nudge:""},
  thanks_all:{trip:"thanks",kind:"multi",result:"Pat and Gus get paid back. Leo, 10, pays half.",label:"Friendsgiving at Pat's",start:"2026-11-26",host:"pat",
    text:"Friendsgiving at Pat's on Nov 26. Pat made the turkey, $140. Gus brought sides and dessert, $90. Mel brought wine, $60. Kim doesn't drink and brings her son Leo (10).",
    people:[
      {id:"pat",name:"Pat",age:null,nights:1,drinks:true},
      {id:"gus",name:"Gus",age:null,nights:1,drinks:true},
      {id:"mel",name:"Mel",age:null,nights:1,drinks:true},
      {id:"kim",name:"Kim",age:null,nights:1,drinks:false},
      {id:"leo",name:"Leo",age:10,nights:1,drinks:false,guardians:["kim"]}],
    expenses:[{kind:"groceries",what:"Turkey",amount:140,by:"pat"},{kind:"groceries",what:"Sides and dessert",amount:90,by:"gus"},{kind:"drinks",what:"Wine",amount:60,by:"mel"}],
    exempt:[], nudge:""},
  thanks_june:{trip:"thanks",kind:"multi",result:"Hal and Ivy paid. The others pay them both back.",label:"Thanksgiving at Grandma June's",start:"2026-11-26",host:"june",
    text:"Thanksgiving at Grandma June's on Nov 26. Hal bought the turkey and groceries, $260. Ivy brought wine, $70. Ivy's partner Cy is coming. Hal brings his kids, Ty (6) and Em (13).",
    people:[
      {id:"june",name:"Grandma June",age:null,nights:1,drinks:true},
      {id:"hal",name:"Hal",age:null,nights:1,drinks:true},
      {id:"ivy",name:"Ivy",age:null,nights:1,drinks:true},
      {id:"cy",name:"Cy",age:null,nights:1,drinks:true},
      {id:"ty",name:"Ty",age:6,nights:1,drinks:false,guardians:["hal"]},
      {id:"em",name:"Em",age:13,nights:1,drinks:false,guardians:["hal"]}],
    expenses:[{kind:"groceries",what:"Turkey and groceries",amount:260,by:"hal"},{kind:"drinks",what:"Wine",amount:70,by:"ivy"}],
    exempt:[], nudge:"Try it: tap Grandma June to treat her this year."}
};
const THEMES={thanks:{tab:"Thanksgiving",def:"thanks",h:"thanksgiving",word:"for Thanksgiving",stamp:"happy Thanksgiving",target:"2026-11-26",until:"to Thanksgiving"},cabin:{tab:"Christmas",def:"cabin",h:"christmas",word:"for Christmas",stamp:"merry Christmas",target:"2026-12-25",until:"to Christmas"},ski:{tab:"New Year's",def:"ski",h:"newyear",word:"for New Year's",stamp:"happy new year",target:"2027-01-01",until:"to midnight"}};
const ICON={
  dice:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3.5" y="3.5" width="17" height="17" rx="3.5"/><g fill="currentColor" stroke="none"><circle cx="8.5" cy="8.5" r="1.6"/><circle cx="15.5" cy="8.5" r="1.6"/><circle cx="8.5" cy="15.5" r="1.6"/><circle cx="15.5" cy="15.5" r="1.6"/></g></svg>',
  caret:'<svg viewBox="0 0 24 24" fill="currentColor"><path d="M6 9h12l-6 7z"/></svg>',
  thanks:'<svg viewBox="0 0 24 24" fill="none" stroke="#E8892B" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"><path d="M12 3l1.6 4 3.2-1.5-1 4 3.7-.4-2.2 3.1 3 1.6-4.2 1 1 3.1-4.1-1.5L12 21l-1-6.6-4.1 1.5 1-3.1-4.2-1 3-1.6-2.2-3.1 3.7.4-1-4 3.2 1.5z"/></svg>',
  cabin:'<svg viewBox="0 0 24 24" fill="none" stroke="#4FD18B" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"><path d="M12 2.5l5 6h-2.5l4 5.5h-3l4 5.5H4.5l4-5.5h-3l4-5.5H7z"/><path d="M12 19.5v2.5"/></svg>',
  all:'<svg viewBox="0 0 24 24" fill="none" stroke="#7FC8A9" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 2.5l2.4 1.8 3-.2.9 2.9 2.4 1.8-1 2.8 1 2.8-2.4 1.8-.9 2.9-3-.2L12 21.5l-2.4-1.8-3 .2-.9-2.9-2.4-1.8 1-2.8-1-2.8 2.4-1.8.9-2.9 3 .2z"/><path d="M8.5 12.2l2.4 2.4 4.8-5"/></svg>',
  out:'<svg viewBox="0 0 24 24" fill="none" stroke="#F07A52" stroke-width="2" stroke-linecap="round"><circle cx="9.5" cy="8" r="3.5"/><path d="M3 20c0-3.6 2.9-6 6.5-6s6.5 2.4 6.5 6"/><path d="M16.5 10.5h5"/></svg>',
  multi:'<svg viewBox="0 0 24 24" fill="none" stroke="#F2C14E" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 8h13l-3-3M20 16H7l3 3"/></svg>',
  ski:'<svg viewBox="0 0 24 24" fill="none" stroke="#F2C14E" stroke-width="2" stroke-linecap="round"><path d="M12 3v5M12 16v5M3 12h5M16 12h5M5.6 5.6l3.2 3.2M15.2 15.2l3.2 3.2M5.6 18.4l3.2-3.2M15.2 8.8l3.2-3.2"/></svg>'};
const DEFAULT_RULES={freeAge:5,halfAge:12,byNights:true,drinksOnly:true,dueDays:7};

let S;
const $=id=>document.getElementById(id);
const esc=s=>String(s).replace(/[&<>"]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"}[c]));
const money=c=>(c<0?"-":"")+"$"+(Math.abs(c)/100).toLocaleString("en-US",{minimumFractionDigits:2,maximumFractionDigits:2});
const fmtDate=d=>d.toLocaleDateString("en-US",{weekday:"short",month:"short",day:"numeric",timeZone:"UTC"});
const nightsTxt=n=>`${n} night${n>1?"s":""}`;
const list=a=>a.length<2?a.join(""):a.slice(0,-1).join(", ")+" and "+a[a.length-1];

/* aityx: the decision below was proven on staging. House rules overwrite its constants; Jev reads only whether the host pays. */
const DECISION={"name":"Example · Holiday split","types":{"Adult":{"id":"string","name":"string","nights":"number > 0","drinks":"boolean"},"Kid":{"id":"string","name":"string","age":"number >= 0","nights":"number > 0","guardians":["string"]},"Expense":{"kind":"lodging|groceries|drinks|other","what":"string","amount":"number >= 0","paid_by":"string"},"Weight":{"id":"string","guardians":["string"],"general":"number","drink":"number"},"Share":{"id":"string","guardians":["string"],"owed":"number"},"Owed":{"id":"string","owed":"number"},"Balance":{"id":"string","net":"number"},"Slice":{"id":"string","i":"number","v":"number"},"Transfer":{"from":"string","to":"string","amount":"number"},"RLine":{"kind":"string","label":"string","ref":"string","value":"number","paid":"number","share":"number","weight":"number"},"LineSet":{"id":"string","lines":["RLine"]},"PersonReceipt":{"id":"string","lines":["RLine"],"owes":"number","rounding":"number"}},"inputs":{"start":{"type":"date","desc":"First day of the trip","from":"trip JSON"},"host":{"type":"string","desc":"Id of the person hosting or booking the trip","from":"trip JSON"},"exempt":{"type":["string"],"desc":"Ids of people the group agreed won't pay","from":"trip JSON"},"people":{"type":["Adult"],"desc":"Adults on the trip, who pay","from":"trip JSON"},"kids":{"type":["Kid"],"desc":"Kids on the trip; their guardians pay their share","from":"trip JSON"},"expenses":{"type":["Expense"],"desc":"What was bought, in USD, and who paid","from":"trip JSON"},"host_not_paying":{"type":"number [0..1]","desc":"Jev probability that the message says the host won't pay","from":"Jev"}},"functions":{"age_weight":{"desc":"Share of a full person's cost for a kid of this age","params":{"age":"number","free_age":"number","half_age":"number"},"returns":"number","body":[["age","=> number","# why"],["<= free_age","0","Kids up to the free age stay free."],["<= half_age","0.5","Kids up to the half age pay half."],["-","1","Older kids pay a full share."]]},"share_of":{"desc":"One person's share of one expense, in USD: drinks by drink weight, everything else by general weight","params":{"amount":"number","kind":"string","wg":"number","wd":"number","gt":"number","dt":"number"},"returns":"number","body":"if kind = \"drinks\" then (if dt = 0 then 0 else amount * wd / dt) else (if gt = 0 then 0 else amount * wg / gt)"}},"decisions":{"free_age":{"type":"number","desc":"Kids at or below this age stay free","expr":"5"},"half_age":{"type":"number","desc":"Kids at or below this age pay half","expr":"12"},"split_by_nights":{"type":"boolean","desc":"Weigh every share by nights stayed?","expr":"true"},"drinkers_split_drinks":{"type":"boolean","desc":"Split drinks only among the people who drink?","expr":"true"},"pay_days_before":{"type":"number","desc":"Days before the trip that transfers are due","expr":"7"},"evidence_threshold":{"type":"number [0..1]","desc":"Minimum Jev probability to treat the host as not paying","expr":"0.8"},"weights":{"type":["Weight"],"desc":"Each person's weight for shared costs (age share times nights) and for drinks (nights, adults who drink)","expr":"concatenate(for p in people return {id: p.id, guardians: [], general: if split_by_nights then p.nights else 1, drink: if not(drinkers_split_drinks) or p.drinks then (if split_by_nights then p.nights else 1) else 0}, for k in kids return {id: k.id, guardians: k.guardians, general: age_weight(k.age, free_age, half_age) * (if split_by_nights then k.nights else 1), drink: 0})"},"general_total":{"type":"number","desc":"Sum of everyone's weight for shared costs","expr":"sum(weights.general)"},"drink_total":{"type":"number","desc":"Sum of everyone's weight for drinks","expr":"sum(weights.drink)"},"shared_cost":{"type":"number","desc":"Lodging, groceries and other costs everyone shares, in USD","expr":"sum(concatenate([0], expenses[kind != \"drinks\"].amount))"},"drinks_cost":{"type":"number","desc":"Drinks cost, in USD","expr":"sum(concatenate([0], expenses[kind = \"drinks\"].amount))"},"shares":{"type":["Share"],"desc":"Each person's own share of the costs before kids and exemptions move, in USD","let":{"general_total":"sum(weights.general)","drink_total":"sum(weights.drink)"},"expr":"for w in weights return {id: w.id, guardians: w.guardians, owed: (if general_total = 0 then 0 else shared_cost * w.general / general_total) + (if drink_total = 0 then 0 else drinks_cost * w.drink / drink_total)}"},"payer_shares":{"type":["Owed"],"desc":"Each adult's share including their part of their kids' shares, split evenly between guardians, in USD","expr":"for p in shares[count(guardians) = 0] return {id: p.id, owed: p.owed + sum(concatenate([0], for k in shares[list contains(guardians, p.id)] return k.owed / count(k.guardians)))}"},"host_exempt":{"type":"boolean","desc":"Does the message establish that the host won't pay?","expr":"host_not_paying >= evidence_threshold"},"exempt_ids":{"type":["string"],"desc":"Ids of the adults who don't pay","expr":"if host_exempt then distinct values(concatenate(exempt, [host])) else exempt"},"exempt_cost_total":{"type":"number","desc":"The shares of the adults who don't pay, in USD","expr":"sum(concatenate([0], payer_shares[list contains(exempt_ids, id)].owed))"},"covering_count":{"type":"number","desc":"How many adults cover the shares of those who don't pay","expr":"count(payer_shares[not(list contains(exempt_ids, id))])"},"balances":{"type":["Balance"],"desc":"What each adult paid minus what they owe, with exempt shares split evenly among the others, in USD","let":{"exempt_cost":"sum(concatenate([0], payer_shares[list contains(exempt_ids, id)].owed))","covering":"count(payer_shares[not(list contains(exempt_ids, id))])"},"expr":"for p in payer_shares return {id: p.id, net: sum(concatenate([0], expenses[paid_by = p.id].amount)) - (if list contains(exempt_ids, p.id) then 0 else p.owed + exempt_cost / covering)}"},"debtors":{"type":["Slice"],"desc":"Adults who owe money, largest first, in USD","expr":"sort((for i in 1..count(balances) return {id: balances[i].id, i: i, v: 0 - balances[i].net})[v > 0], function(x, y) x.v > y.v or (x.v = y.v and x.i < y.i))"},"creditors":{"type":["Slice"],"desc":"Adults who are owed money, largest first, in USD","expr":"sort((for i in 1..count(balances) return {id: balances[i].id, i: i, v: balances[i].net})[v > 0], function(x, y) x.v > y.v or (x.v = y.v and x.i < y.i))"},"transfers":{"type":["Transfer"],"desc":"Who pays whom, in USD rounded to cents: the largest debts settle the largest credits first","let":{"debt_ends":"if count(debtors) = 0 then [] else for k in 1..count(debtors) return sum(sublist(debtors.v, 1, k))","credit_ends":"if count(creditors) = 0 then [] else for k in 1..count(creditors) return sum(sublist(creditors.v, 1, k))"},"expr":"if count(debtors) = 0 or count(creditors) = 0 then [] else (for i in 1..count(debtors), j in 1..count(creditors) return {from: debtors[i].id, to: creditors[j].id, amount: decimal(max(0, min(debt_ends[i], credit_ends[j]) - max(debt_ends[i] - debtors[i].v, credit_ends[j] - creditors[j].v)), 2)})[amount > 0]"},"pay_by":{"type":"date","desc":"Date all transfers are due","expr":"start - pay_days_before * duration(\"P1D\")"},"receipt_lines":{"type":["LineSet"],"desc":"Each adult's receipt, line by line, in USD: their share of each expense, their kids' shares, their part of who isn't paying, and what they bought minus their own share of it","expr":"for p in people return {id: p.id, lines: if list contains(exempt_ids, p.id) then (for e in expenses[paid_by = p.id] return {kind: \"bought_exempt\", label: e.what, ref: e.kind, value: decimal(0 - e.amount, 2), paid: e.amount, share: 0, weight: 0}) else concatenate(for e in expenses[paid_by != p.id] return {kind: if e.kind = \"drinks\" and (weights[id = p.id])[1].drink = 0 then \"nodrink\" else \"share\", label: e.what, ref: e.kind, value: decimal(share_of(e.amount, e.kind, (weights[id = p.id])[1].general, (weights[id = p.id])[1].drink, general_total, drink_total), 2), paid: 0, share: 0, weight: 0}, for k in kids[list contains(guardians, p.id)] return {kind: \"kid\", label: k.id, ref: \"\", value: decimal((shares[id = k.id])[1].owed / count(k.guardians), 2), paid: 0, share: 0, weight: age_weight(k.age, free_age, half_age)}, if count(exempt_ids) > 0 then [{kind: \"cover\", label: \"\", ref: \"\", value: decimal(exempt_cost_total / covering_count, 2), paid: 0, share: 0, weight: covering_count}] else [], for e in expenses[paid_by = p.id] return {kind: \"bought\", label: e.what, ref: e.kind, value: decimal(share_of(e.amount, e.kind, (weights[id = p.id])[1].general, (weights[id = p.id])[1].drink, general_total, drink_total) - e.amount, 2), paid: e.amount, share: decimal(share_of(e.amount, e.kind, (weights[id = p.id])[1].general, (weights[id = p.id])[1].drink, general_total, drink_total), 2), weight: 0})}"},"receipts":{"type":["PersonReceipt"],"desc":"Each adult's receipt with what they owe overall (negative means they get money back) and the cents left over from rounding each line","expr":"for r in receipt_lines return {id: r.id, lines: r.lines, owes: sum(concatenate([0], transfers[from = r.id].amount)) - sum(concatenate([0], transfers[to = r.id].amount)), rounding: decimal(sum(concatenate([0], transfers[from = r.id].amount)) - sum(concatenate([0], transfers[to = r.id].amount)) - sum(concatenate([0], r.lines.value)), 2)}"}}};
const QUESTIONS={"host_not_paying":{"type":"noul","instructions":"Does message say that the host, the person in people whose id equals host, will not pay a share of the trip costs? Do not calculate amounts or apply split rules.","criteria":{"true":"The message says the host won't pay or contribute, for example because it is their house.","false":"The message says the host pays like everyone else, or does not say the host won't pay."}}};

let REC_MODE=/record/i.test(location.hash+location.search); // team only: add #record to the address to see the recording buttons
addEventListener("hashchange",()=>{ REC_MODE=/record/i.test(location.hash+location.search); connectUI(); });
// The key: the one every aityx demo shares, set on the demos page (../#aityx-key)
// and kept in this origin's storage, else the index server's dev key through
// its proxy (aityx-js, as packages/aityx_web does for the Flutter demos). The
// page never sees a key: aityx.js makes the calls and the status light checks.
const LIVE={seq:0,timer:0,call:null,state:null};
const live=()=>!!(LIVE.state&&LIVE.state.ok);
const KEYSTAT={ready:"ok",noKey:"",rejected:"bad",unreachable:"bad",failing:"bad"};
function keyStatus(){
  const st=LIVE.state, n=$("keystat");
  const msg=!st?"Checking the aityx key…"
    :st.kind==="ready"?`Connected to aityx with ${st.whose}${st.url?` (${hostOf(st.url)})`:""}.`
    :st.kind==="noKey"?"No aityx key yet. Set yours on the demos page: every aityx demo uses it."
    :st.kind==="rejected"?`aityx didn't accept ${st.whose}: ${st.detail}. Set another on the demos page.`
    :`aityx isn't answering: ${st.detail}.`;
  n.hidden=false; n.className="keystat "+(st?KEYSTAT[st.kind]||"bad":"wait"); n.textContent=msg;
  $("mode").classList.toggle("on",live()); $("setkey").textContent=st&&st.kind==="ready"&&st.source==="user"?"Change key":"Set your key";
}
const hostOf=u=>{ try{ return new URL(u).host; }catch(_){ return u; } };
function noteAuth(res){ if(res.status===401||res.status===403) aityx.recheck(); }
// One systemone call through aityx-js: {res:{status,ok}, data}. Throws an Error
// whose message says why when no answer came (or there's no key).
async function post(body){
  const a=await aityx.systemone(body);
  return {res:{status:a.status,ok:a.ok},data:a.json};
}
function liveNote(t,cls){ const n=$("live"); n.className="live"+(cls?" "+cls:""); n.textContent=t; }
function connectUI(){
  $("recall").hidden=!(live()&&REC_MODE); $("mode").textContent=live()?"Live · aityx":"Prototype";
  if(S){ lockInputs(); setNote(false); }
  keyStatus();
}
function liveDecision(){
  const d=structuredClone(DECISION), r=S.rules, set=(k,v)=>{ d.decisions[k].expr=String(v); };
  set("free_age",r.freeAge); set("half_age",r.halfAge); set("split_by_nights",r.byNights); set("drinkers_split_drinks",r.drinksOnly); set("pay_days_before",r.dueDays);
  return d;
}
// read: Jev + Decision on the message (once per trip). Otherwise Decision-only: what Jev found is already in S.exempt, so no AI call.
function liveState(read){
  const st={start:S.start,host:S.host,exempt:read&&!S.exemptByYou?[]:[...S.exempt],
    people:S.people.filter(p=>!isKid(p)).map(p=>({id:p.id,name:p.name,nights:p.nights,drinks:p.drinks})),
    kids:S.people.filter(isKid).map(k=>({id:k.id,name:k.name,age:k.age,nights:k.nights,guardians:k.guardians})),
    expenses:S.expenses.map(e=>({kind:e.kind,what:e.what,amount:e.amount,paid_by:e.by}))};
  if(read) st.message=$("msg").value; else st.host_not_paying=0;
  return st;
}
async function settleLive(read,afterRead){
  if(!live()) return;
  clearTimeout(LIVE.timer);
  const seq=++LIVE.seq, body={decision:liveDecision()};
  if(read) body.questions=QUESTIONS;
  body.state=liveState(read);
  liveNote(read?"aityx is reading the message…":"aityx is settling…");
  const t0=performance.now();
  let res,data;
  try{
    ({res,data}=await post(body));
  }catch(e){ if(seq===LIVE.seq) liveNote(`Couldn't reach aityx (${e.message}). Showing the split from your browser.`,"warn"); return; }
  if(seq!==LIVE.seq) return;
  noteAuth(res);
  LIVE.call={req:body,res:data,status:res.status};
  const err=!res.ok?(data&&(data.detail||data.title))||`HTTP ${res.status}`:data&&data.decision_error?(data.decision_error.message||data.decision_error.code):null;
  if(err){ liveNote(`aityx couldn't settle this: ${err}. The amounts below are not from aityx.`,"warn"); renderCall(); return; }
  const a=data.answers;
  if(read){ S.exempt=new Set(a.exempt_ids.value); S.exemptByYou=false; renderRules(); S.R=compute(); }
  S.R.tx=a.transfers.value.map(t=>({from:t.from,to:t.to,c:Math.round(Number(t.amount)*100)}));
  if(a.receipts) applyReceipts(S.R,a.receipts.value);
  S.R.due=new Date(a.pay_by.date+"T00:00:00Z");
  render(false);
  const ms=Math.round(performance.now()-t0), p=a.host_not_paying&&a.host_not_paying.noul;
  liveNote(afterRead?`Jev read the group chat (${LIVE.readN} questions, ${LIVE.readMs} ms). aityx settled it with your house rules (${ms} ms).`
    :read?`Settled by aityx. Jev read the message: ${Math.round(p*100)}% that the host isn't paying. ${ms} ms`
    :`Settled by aityx with your house rules. No AI call. ${ms} ms`,"ok");
}
// Real aityx calls recorded with a key, shown to visitors without one. Filled with "Copy this call as a recording".
const RECORDINGS=recordings;
// For the team: runs every example untouched with your key and saves the real calls as one file.
async function recordAll(){
  if(!live()) return;
  const out={}, keys=Object.keys(SAMPLES);
  for(let i=0;i<keys.length;i++){ const k=keys[i];
    load(k); document.body.classList.remove("pending"); LIVE.rec=null;
    toast(`Recording example ${i+1} of ${keys.length}…`);
    run(); await readLive();
    if(!LIVE.rec||LIVE.rec.key!==k){ toast(`Stopped on "${SAMPLES[k].label}". See the note under the results.`); return; }
    out[k]=LIVE.rec; }
  const a=document.createElement("a"); a.href=URL.createObjectURL(new Blob([JSON.stringify(out)],{type:"application/json"})); a.download="holiday-recordings.json";
  document.body.appendChild(a); a.click(); a.remove();
  liveNote(`Recorded all ${keys.length} examples with real aityx calls. Saved holiday-recordings.json to your Downloads.`,"ok");
}

// Receipt lines come from aityx (the decision's "receipts"); the page only words them.
function applyReceipts(R,receipts){
  if(!Array.isArray(receipts)) return;
  const r=S.rules, byId=R.byId, cents=v=>Math.round(Number(v)*100);
  const drinkers=S.people.filter(p=>!isKid(p)&&(!r.drinksOnly||p.drinks)&&canDrink(p)).length;
  const exNames=list(S.people.filter(p=>S.exempt.has(p.id)).map(p=>p.name));
  for(const rc of receipts){
    const p=byId[rc.id]; if(!p) continue;
    const dsrc=p.edited.drinks?"you":live()&&!S.jevRead?"rule":"ai", xsrc=S.exemptByYou?"you":"ai";
    const shareWhy=l=>l.ref==="drinks"?(r.drinksOnly?`shared by the ${drinkers} people who drink`+(r.byNights&&multiNight()?`, ${nightsTxt(p.nights)}`:""):"shared by all adults")
      :(r.byNights&&multiNight()?`${nightsTxt(p.nights)} of the trip`:"split evenly");
    const L=rc.lines.map(l=>{ const c=cents(l.value);
      if(l.kind==="share") return {t:l.label,c,why:shareWhy(l),src:l.ref==="drinks"&&r.drinksOnly?dsrc:"rule"};
      if(l.kind==="nodrink") return {t:l.label,c,why:"doesn't drink",src:dsrc};
      if(l.kind==="kid"){ const k=byId[l.label]||{name:l.label,age:"",guardians:[]}, others=(k.guardians||[]).filter(g=>g!==p.id).map(g=>byId[g]&&byId[g].name).filter(Boolean);
        const base=l.weight===0?`kids up to ${r.freeAge} stay free`:l.weight===.5?`kids up to ${r.halfAge} pay half`:`over ${r.halfAge}, full price`;
        return {t:`For ${k.name}, ${k.age}`,c,why:base+(others.length&&l.weight>0?`, split with ${list(others)}`:""),src:"rule"}; }
      if(l.kind==="cover") return {t:`Your part of ${exNames}'s share`,c,why:`${exNames} ${S.exempt.size>1?"don't":"doesn't"} pay, split ${l.weight} ways`,src:xsrc};
      if(l.kind==="bought_exempt") return {t:`${l.label} · you bought it`,c,why:`You paid ${money(cents(l.paid))}. You're not paying this time, so the group pays you back all of it.`,src:xsrc};
      const share=cents(l.share), back=-c;
      return {t:`${l.label} · you bought it`,c,why:share===0?(l.ref==="drinks"&&!p.drinks?`You paid ${money(cents(l.paid))}. You don't drink, so the group pays you back all of it.`:`You paid ${money(cents(l.paid))}. None of it is your share, so the group pays you back all of it.`)
        :`You paid ${money(cents(l.paid))}. Your share is ${money(share)}, so the group pays you back ${money(back)}.`,src:l.ref==="drinks"&&r.drinksOnly?dsrc:"rule"}; });
    const rd=cents(rc.rounding); if(rd) L.push({t:"Rounding",c:rd,why:"cents left over from splitting evenly",src:"rule"});
    R.lines[rc.id]=L; R.net[rc.id]=-cents(rc.owes);
  }
  R.fromAityx=true;
}
function applyRec(R,rec){ R.tx=rec.transfers.map(t=>({from:t.from,to:t.to,c:Math.round(Number(t.amount)*100)})); R.due=new Date(rec.pay_by+"T00:00:00Z"); if(rec.receipts) applyReceipts(R,rec.receipts); }
function showRecorded(){
  const rec=RECORDINGS[S.key];
  document.body.classList.toggle("norec",!rec);
  if(!rec){ liveNote("This trip has no recorded aityx call yet. Connect a key above and aityx splits it live.","warn"); renderCall(); return; }
  S.exempt=new Set(rec.exempt); S.people.forEach(p=>{ if(p.id in rec.drinks) p.drinks=rec.drinks[p.id]; });
  S.jevRead=true; S.recorded=rec;
  renderFacts(); renderRules(); S.R=compute(); applyRec(S.R,rec); render(false);
  liveNote(`Recorded from a real aityx call on ${rec.when}. Connect a key above to change the rules and run it live.`,"ok");
}
function lockInputs(){
  const lk=!live(); document.body.classList.toggle("locked",lk);
  $("msg").readOnly=lk; $("readchat").disabled=lk||READING;
  document.querySelectorAll("#rules input,#rules button,#ppl input,#ppl select,#ppl button,#exp input,#exp select,#exp button,.addrow button").forEach(el=>el.disabled=lk);
}
function renderDecisionView(){
  const d=liveDecision(), pick=["free_age","half_age","split_by_nights","drinkers_split_drinks","pay_days_before","evidence_threshold"];
  if(typeof VIEW!=="undefined"&&VIEW==="full"){ $("dview").innerHTML=hl(d); return; }
  $("dview").innerHTML=hl({functions:{age_weight:{desc:d.functions.age_weight.desc,body:d.functions.age_weight.body}},
    decisions:Object.fromEntries(pick.map(k=>[k,{desc:d.decisions[k].desc,expr:d.decisions[k].expr}]))});
}
function captureRecording(){
  const c=LIVE.call, untouched=$("msg").value===SAMPLES[S.key].text&&JSON.stringify(S.rules)===JSON.stringify(DEFAULT_RULES)
    &&!S.people.some(p=>Object.keys(p.edited).length)&&!S.expenses.some(e=>e.edited)&&!S.exemptByYou&&!S.listChanged;
  if(!untouched||!c||c.status!==200||!c.res||c.res.decision_error||!c.res.answers) return;
  LIVE.rec={key:S.key,when:new Date().toISOString().slice(0,10),exempt:[...S.exempt],
    drinks:Object.fromEntries(S.people.filter(p=>!isKid(p)&&canDrink(p)).map(p=>[p.id,p.drinks])),
    transfers:c.res.answers.transfers.value,pay_by:c.res.answers.pay_by.date,receipts:c.res.answers.receipts&&c.res.answers.receipts.value,
    read:{req:LIVE.read.req,res:LIVE.read.res},settle:{req:c.req,res:c.res}};
  $("rec").hidden=!REC_MODE;
}
const EVIDENCE=0.8; // same cut-off as the decision's evidence_threshold
function jevQuestions(){
  const q={};
  S.people.filter(p=>!isKid(p)).forEach(p=>{
    q[`${p.id}_not_paying`]={type:"noul",
      instructions:`Does message say that ${p.name} (id ${p.id} in people) will not pay a share of the trip costs? Do not calculate amounts or apply split rules.`,
      criteria:{"true":`The message says ${p.name} won't pay or contribute, for example because it is their house or the group is treating them.`,
                "false":`The message says ${p.name} pays like everyone else, or does not say ${p.name} won't pay.`}};
    if(canDrink(p)) q[`${p.id}_no_drinks`]={type:"noul",
      instructions:`Does message say that ${p.name} (id ${p.id} in people) does not drink alcohol on this trip?`,
      criteria:{"true":`The message says ${p.name} doesn't drink, stopped drinking, or skips the alcohol.`,
                "false":`The message says ${p.name} drinks, or does not say ${p.name} doesn't drink.`}};
  });
  return q;
}
// Step 1: Jev reads the message (one noul question per person). Step 2: the same proven decision settles, no AI.
async function readLive(){
  if(!live()) return;
  clearTimeout(LIVE.timer);
  const seq=++LIVE.seq, questions=jevQuestions();
  const body={questions,state:{message:$("msg").value,people:S.people.filter(p=>!isKid(p)).map(p=>({id:p.id,name:p.name}))}};
  liveNote("Jev is reading the group chat…");
  const t0=performance.now(); let res,data;
  try{
    ({res,data}=await post(body));
  }catch(e){ if(seq===LIVE.seq) liveNote(`Couldn't reach aityx (${e.message}). Showing the split from your browser.`,"warn"); return; }
  if(seq!==LIVE.seq) return;
  noteAuth(res);
  LIVE.read={req:body,res:data,status:res.status};
  const a=data&&data.answers, pr=k=>a&&a[k]&&typeof a[k].noul==="number"?a[k].noul:null;
  if(!res.ok||!a||Object.keys(questions).every(k=>pr(k)===null)){
    liveNote(`Jev: ${(data&&(data.detail||data.title))||"HTTP "+res.status+", no answers"}. The amounts below are not from aityx.`,"warn"); renderCall(); return; }
  if(!S.exemptByYou) S.exempt=new Set(S.people.filter(p=>!isKid(p)&&(pr(`${p.id}_not_paying`)||0)>=EVIDENCE).map(p=>p.id));
  S.people.forEach(p=>{ if(!isKid(p)&&canDrink(p)&&!p.edited.drinks) p.drinks=(pr(`${p.id}_no_drinks`)||0)<EVIDENCE; });
  S.jevRead=true; LIVE.readMs=Math.round(performance.now()-t0); LIVE.readN=Object.keys(questions).length;
  renderFacts(); renderRules(); S.R=compute(); render(false);
  await settleLive(false,true);
  captureRecording();
}
function queueLive(){ clearTimeout(LIVE.timer); LIVE.timer=setTimeout(()=>settleLive(false),350); }
aityx.mountLight($("light"));
for(const id of ["setkey","keylink"]) $(id).addEventListener("click",e=>{ e.preventDefault(); aityx.openKeyPage(); });
$("version").textContent="v"+__APP_VERSION__;
// The key changed (here, on the demos page, or in another tab), or the light
// checked again: unlock or lock, and once it works, run the trip on aityx.
aityx.onState(st=>{
  const was=live(); LIVE.state=st; connectUI();
  if(!S) return;
  if(live()&&!was){ LIVE.call=null; LIVE.read=null; if(!document.body.classList.contains("pending")) readLive(); else renderCall(); }
  else if(!live()&&was){ LIVE.call=null; LIVE.read=null; LIVE.seq++; clearTimeout(LIVE.timer); load(S.key); }
});
connectUI();

// The trip reader: a small LLM on this device (transformers.js, reader.js)
// turns the chat into the lists (who comes, for how many nights, the kids'
// ages and parents, what was spent and by whom). Then, as for a sample, Jev
// reads who isn't paying and who doesn't drink, and the house rules settle.
let READING=false;
function readerNote(t,cls){ const n=$("readnote"); n.hidden=!t; n.className="note readnote"+(cls?" "+cls:""); n.textContent=t||""; }
async function readChat(){
  const text=$("msg").value.trim();
  if(!text||!live()||READING) return;
  READING=true; $("readchat").disabled=true; $("readchat").classList.remove("go");
  readerNote("Starting the trip reader…");
  try{
    const out=await reader.read(text,{
      onProgress:p=>readerNote(`Loading the trip reader: ${Math.round(p*100)}% (downloaded the first time only, then your browser keeps it)`),
      onLoaded:d=>readerNote(`Reading the chat on this device (${d==="webgpu"?"on the GPU":"on the CPU, slower"})…`),
      onToken:n=>readerNote(`Reading the chat on this device… ${n} token${n===1?"":"s"}`)});
    applyTrip(out.trip);
    const t=out.trip, adults=t.people.filter(p=>!p.guardians.length).length, kids=t.people.length-adults;
    readerNote(`Read on this device in ${(out.ms/1000).toFixed(1)} s: ${adults} adult${adults===1?"":"s"}${kids?`, ${kids} kid${kids===1?"":"s"}`:""} and ${t.expenses.length} expense${t.expenses.length===1?"":"s"}${t.notes.length?` (${t.notes.join("; ")})`:""}. Check the lists: fix anything it got wrong.`,"ok");
    document.body.classList.remove("pending"); run(); readLive();
  }catch(e){
    readerNote(`The trip reader couldn't read it: ${e.message}. Write it more plainly, or fix the lists by hand.`,"warn");
  }finally{ READING=false; $("readchat").disabled=!live(); }
}
function applyTrip(t){
  Object.assign(S,{start:t.start,host:t.host,label:"Your trip",nudge:"",
    people:t.people.map(p=>({...p,edited:{}})),expenses:t.expenses.map((e,i)=>({...e,i,edited:false})),
    exempt:new Set(),exemptByYou:false,jevRead:false,listChanged:true,recorded:null,focus:null});
  LIVE.call=null; LIVE.read=null;
  $("casetag").innerHTML=`${ICON.all}<span><b>Your trip</b> · read from your chat, on this device</span>`;
  renderFacts(); renderRules();
}
function load(key){
  const s=SAMPLES[key];
  S={key,start:s.start,host:s.host,label:s.label,nudge:s.nudge,
    people:s.people.map(p=>({guardians:[],...p,edited:{}})),
    expenses:s.expenses.map((e,i)=>({...e,i,edited:false})),
    exempt:new Set(s.exempt),exemptByYou:false,jevRead:false,rules:{...DEFAULT_RULES},focus:null,listChanged:false,n:0};
  const th=THEMES[s.trip]; document.documentElement.dataset.holiday=th.h; $("hword").textContent=th.word; FX.set(th.h); countdown(th);
  $("msg").value=s.text; setNote(false); readerNote(""); $("readchat").classList.remove("go");
  $("tabs").innerHTML=Object.entries(THEMES).map(([t,v])=>`<button class="tab" type="button" data-k="${v.def}" aria-pressed="${t===s.trip}">${esc(v.tab)}</button>`).join("");
  $("casetag").innerHTML=`${ICON[s.kind]}<span><b>${esc(s.label)}</b> · ${esc(s.result)}</span>`;
  $("fill-menu").innerHTML=Object.entries(SAMPLES).filter(([,v])=>v.trip===s.trip).map(([k,v])=>`<button type="button" role="menuitemradio" aria-checked="${k===key}" data-pick="${k}">${ICON[v.kind]}<span>${esc(v.label)}<small>${esc(v.result)}</small></span></button>`).join("");
  S.recorded=null; LIVE.call=null; LIVE.read=null; menu(false);
  document.body.classList.add("pending"); document.body.classList.remove("norec");
  renderFacts(); renderRules(); run(true);
}
function setNote(warn){
  $("msgnote").className="note"+(warn?" warn":"");
  $("msgnote").textContent=live()?"The family wrote this, or write your own trip. The trip reader, on this device, reads who comes and what was spent; Jev, the aityx AI, reads who isn't paying and who doesn't drink."
    :"The family wrote this. Jev, the aityx AI, reads it for who isn't paying and who doesn't drink. Set your aityx key to write your own trip.";
}

const isKid=p=>p.guardians.length>0;
const canDrink=p=>p.age==null||p.age>=21;
function weight(p,r){ if(p.age==null) return 1; if(p.age<=r.freeAge) return 0; if(p.age<=r.halfAge) return .5; return 1; }
function alloc(total,ws){
  const sum=ws.reduce((a,b)=>a+b,0); if(!sum) return ws.map(()=>0);
  const raw=ws.map(w=>total*w/sum), base=raw.map(Math.floor); let rem=total-base.reduce((a,b)=>a+b,0);
  raw.map((v,i)=>[v-base[i],i]).sort((a,b)=>b[0]-a[0]).forEach(([,i])=>{if(rem>0&&ws[i]>0){base[i]++;rem--;}});
  return base;
}

const multiNight=()=>Math.max(...S.people.map(p=>p.nights))>1; // a one-day event has no nights to split by
function compute(){
  const r=S.rules,P=S.people,byId=Object.fromEntries(P.map(p=>[p.id,p]));
  const payers=P.filter(p=>!isKid(p)), lines={}, owe={}, paid={};
  payers.forEach(p=>{lines[p.id]=[];owe[p.id]=0;paid[p.id]=0;});
  const kidCost={}; P.filter(isKid).forEach(k=>kidCost[k.id]=0);
  for(const e of S.expenses){
    const cents=Math.round(e.amount*100); let pool,ws;
    if(e.kind==="drinks"){ pool=P.filter(p=>canDrink(p)&&(!r.drinksOnly||p.drinks)); ws=pool.map(p=>r.byNights?p.nights:1); }
    else { pool=P; ws=pool.map(p=>weight(p,r)*(r.byNights?p.nights:1)); }
    const a=alloc(cents,ws);
    pool.forEach((p,i)=>{
      if(isKid(p)){ kidCost[p.id]+=a[i]; return; }
      let why;
      if(e.kind==="drinks") why=r.drinksOnly?`shared by the ${pool.length} people who drink`+(r.byNights&&multiNight()?`, ${nightsTxt(p.nights)}`:""):`shared by all adults`;
      else why=r.byNights&&multiNight()?`${nightsTxt(p.nights)} of the trip`:`split evenly`;
      lines[p.id].push({t:e.what,ex:e.i,c:a[i],why,src:e.kind==="drinks"&&r.drinksOnly?(p.edited.drinks?"you":live()&&!S.jevRead?"rule":"ai"):"rule"}); owe[p.id]+=a[i];
    });
    if(e.kind==="drinks") payers.filter(p=>!pool.includes(p)).forEach(p=>lines[p.id].push({t:e.what,ex:e.i,c:0,why:"doesn't drink",src:p.edited.drinks?"you":live()&&!S.jevRead?"rule":"ai"}));
  }
  for(const k of P.filter(isKid)){
    const g=k.guardians, parts=alloc(kidCost[k.id],g.map(()=>1)), w=weight(k,r);
    const base=w===0?`kids up to ${r.freeAge} stay free`:w===.5?`kids up to ${r.halfAge} pay half`:`over ${r.halfAge}, full price`;
    g.forEach((gid,i)=>{ const others=g.filter(x=>x!==gid).map(x=>byId[x].name);
      lines[gid].push({t:`For ${k.name}, ${k.age}`,c:parts[i],why:base+(others.length&&w>0?`, split with ${list(others)}`:""),src:"rule"}); owe[gid]+=parts[i]; });
  }
  const ex=payers.filter(p=>S.exempt.has(p.id)), cover=payers.filter(p=>!S.exempt.has(p.id));
  for(const x of ex){
    const c=owe[x.id]; if(!c) continue;
    lines[x.id].push({t:"Covered by everyone else",c:-c,why:`${x.name} doesn't pay`,src:S.exemptByYou?"you":"ai"}); owe[x.id]=0;
    const parts=alloc(c,cover.map(()=>1));
    cover.forEach((p,i)=>{ lines[p.id].push({t:`Your part of ${x.name}'s share`,c:parts[i],why:`${x.name} doesn't pay, split ${cover.length} ways`,src:S.exemptByYou?"you":"ai"}); owe[p.id]+=parts[i]; });
  }
  for(const e of S.expenses){
    const c=Math.round(e.amount*100), L=lines[e.by]; paid[e.by]+=c;
    if(S.exempt.has(e.by)){ L.push({t:`${e.what} · you bought it`,c:-c,why:`You paid ${money(c)}. You're not paying this time, so the group pays you back all of it.`,src:S.exemptByYou?"you":"ai",bought:true}); continue; }
    const k=L.findIndex(l=>l.ex===e.i), sh=k<0?null:L[k], share=sh?sh.c:0;
    if(k>=0) L.splice(k,1);
    const back=c-share, why=share===0?(sh&&sh.why==="doesn't drink"?`You paid ${money(c)}. You don't drink, so the group pays you back all of it.`:`You paid ${money(c)}. None of it is your share, so the group pays you back all of it.`)
      :`You paid ${money(c)}. Your share is ${money(share)}, so the group pays you back ${money(back)}.`;
    L.push({t:`${e.what} · you bought it`,c:-back,why,src:sh?sh.src:"rule",bought:true});
  }
  // whoever isn't paying only sees what they bought; their shares are covered by the others
  for(const x of ex) lines[x.id]=lines[x.id].filter(l=>l.bought);
  const net={}; payers.forEach(p=>net[p.id]=paid[p.id]-owe[p.id]);
  const debt=payers.filter(p=>net[p.id]<0).map(p=>({id:p.id,v:-net[p.id]})).sort((a,b)=>b.v-a.v);
  const cred=payers.filter(p=>net[p.id]>0).map(p=>({id:p.id,v:net[p.id]})).sort((a,b)=>b.v-a.v);
  const tx=[]; let i=0,j=0;
  while(i<debt.length&&j<cred.length){ const v=Math.min(debt[i].v,cred[j].v); if(v>0) tx.push({from:debt[i].id,to:cred[j].id,c:v});
    debt[i].v-=v; cred[j].v-=v; if(!debt[i].v) i++; if(!cred[j].v) j++; }
  const start=new Date(S.start+"T00:00:00Z"), due=new Date(start.getTime()-r.dueDays*864e5);
  return {payers,lines,net,tx,due,start,byId};
}

function renderRules(){
  const r=S.rules, adults=S.people.filter(p=>!isKid(p)), hasKids=S.people.some(isKid);
  const seg=(id,on,a,b)=>`<span class="seg" role="group"><button type="button" data-seg="${id}" data-v="1" aria-pressed="${on}">${a}</button><button type="button" data-seg="${id}" data-v="0" aria-pressed="${!on}">${b}</button></span>`;
  $("rules").innerHTML=`
  ${hasKids?`<div class="rule">Kids up to age <input type="number" id="r-free" min="0" max="17" value="${r.freeAge}" aria-label="Kids stay free up to age"> stay free</div>
  <div class="rule">Kids up to age <input type="number" id="r-half" min="0" max="20" value="${r.halfAge}" aria-label="Kids pay half up to age"> pay half</div>`:""}
  ${multiNight()?`<div class="rule">The stay is split ${seg("nights",r.byNights,"by nights","the same for everyone")}</div>`:""}
  <div class="rule">Drinks are paid by ${seg("drinks",r.drinksOnly,"people who drink","all adults")}</div>
  <div class="rule">Everyone pays <input type="number" id="r-due" min="0" max="60" value="${r.dueDays}" aria-label="Days before the trip"> days before the trip</div>
  <div class="rule">Who doesn't pay?
    ${adults.map(p=>`<button type="button" class="chip" data-x="${p.id}" aria-pressed="${S.exempt.has(p.id)}">${esc(p.name)}</button>`).join("")}
    ${S.nudge?`<div class="nudge" id="nudge">${esc(S.nudge)}</div>`:""}</div>`;
  lockInputs(); renderDecisionView();
}
function renderFacts(){
  const P=S.people, adults=P.filter(p=>!isKid(p)), byId=Object.fromEntries(P.map(p=>[p.id,p]));
  const ed=x=>x?`<span class="edited">changed</span>`:"";
  const used=id=>S.expenses.some(e=>e.by===id)||P.some(k=>k.guardians.includes(id));
  $("ppl").innerHTML=`<thead><tr><th>Who</th><th>Age</th>${multiNight()?"<th>Nights</th>":""}<th>Drinks</th><th></th></tr></thead><tbody>`+
    P.map(p=>`<tr><td><input type="text" maxlength="24" data-p="${p.id}" data-f="name" value="${esc(p.name)}" aria-label="Name">${isKid(p)&&p.guardians.length>1?`<small>with ${esc(list(p.guardians.map(g=>byId[g].name)))}</small>`:""}${isKid(p)&&p.guardians.length<2?`<small>with <select data-p="${p.id}" data-f="guardian" aria-label="${esc(p.name)} comes with">${adults.map(a=>`<option value="${a.id}" ${p.guardians[0]===a.id?"selected":""}>${esc(a.name)}</option>`).join("")}</select></small>`:""}</td>
    <td>${p.age==null?`<small>adult</small>`:`<input type="number" min="0" max="20" id="age-${p.id}" data-p="${p.id}" data-f="age" value="${p.age}" aria-label="${esc(p.name)} age">${ed(p.edited.age)}`}</td>
    ${multiNight()?`<td><input type="number" min="1" max="30" id="n-${p.id}" data-p="${p.id}" data-f="nights" value="${p.nights}" aria-label="${esc(p.name)} nights">${ed(p.edited.nights)}</td>`:""}
    <td>${canDrink(p)?`<input type="checkbox" id="d-${p.id}" data-p="${p.id}" data-f="drinks" ${p.drinks?"checked":""} aria-label="${esc(p.name)} drinks">${ed(p.edited.drinks)}`:`<small>under 21</small>`}</td>
    <td><button class="x" type="button" data-delp="${p.id}" aria-label="Remove ${esc(p.name)}" ${used(p.id)||adults.length<2&&!isKid(p)?`title="Paid for something or brings a kid, so they stay"`:""}>×</button></td></tr>`).join("")+`</tbody>`;
  const kinds={lodging:"Stay",groceries:"Groceries",drinks:"Drinks",other:"Other"};
  $("exp").innerHTML=`<thead><tr><th>Expense</th><th>Type</th><th>Paid by</th><th>Amount</th><th></th></tr></thead><tbody>`+
    S.expenses.map(e=>`<tr><td><input type="text" maxlength="30" data-e="${e.i}" data-ef="what" value="${esc(e.what)}" aria-label="Expense"></td>
    <td><select data-e="${e.i}" data-ef="kind" aria-label="${esc(e.what)} type">${Object.entries(kinds).map(([k,l])=>`<option value="${k}" ${e.kind===k?"selected":""}>${l}</option>`).join("")}</select></td>
    <td><select data-e="${e.i}" data-ef="by" aria-label="${esc(e.what)} paid by">${adults.map(a=>`<option value="${a.id}" ${e.by===a.id?"selected":""}>${esc(a.name)}</option>`).join("")}</select></td>
    <td><input type="number" class="money" min="0" step="1" id="e-${e.i}" data-e="${e.i}" value="${e.amount}" aria-label="${esc(e.what)} amount">${ed(e.edited)}</td>
    <td><button class="x" type="button" data-dele="${e.i}" aria-label="Remove ${esc(e.what)}" ${S.expenses.length<2?"disabled":""}>×</button></td></tr>`).join("")+`</tbody>`;
  lockInputs();
}
function listChanged(){ S.listChanged=true; S.expenses.forEach((e,i)=>e.i=i); renderFacts(); renderRules(); run(); }

let lastTx="";
function run(first){
  S.R=compute(); if(!live()&&S.recorded) applyRec(S.R,S.recorded); render(first); renderDecisionView();
  if(document.body.classList.contains("pending")) return;
  if(live()) queueLive();
}
function render(first){
  const R=S.R;
  const sig=JSON.stringify(R.tx); if(!first&&sig!==lastTx){ const rc=$("receipt"); rc.classList.remove("pulse"); void rc.offsetWidth; rc.classList.add("pulse"); } lastTx=sig;
  if(!S.focus||!R.payers.find(p=>p.id===S.focus)) S.focus=(R.tx[0]||{from:R.payers[0].id}).from;
  const amt=p=>{ const n=R.net[p.id]; return n<0?`owes ${money(-n)}`:n>0?`gets ${money(n)}`:S.exempt.has(p.id)?"doesn't pay":"even"; };
  const xm=THEMES[SAMPLES[S.key].trip].h==="christmas";
  $("who").className=xm?"stockings":"people";
  $("who").innerHTML=R.payers.map((p,i)=>xm?`<button type="button" class="stocking" data-w="${p.id}" aria-pressed="${p.id===S.focus}" aria-label="${esc(p.name)}'s receipt">${stockingSVG(i)}<span>${esc(p.name)}<small class="who-amt">${amt(p)}</small></span></button>`
    :`<button type="button" class="tab" data-w="${p.id}" aria-pressed="${p.id===S.focus}">${esc(p.name)}<small class="who-amt">${amt(p)}</small></button>`).join("");
  renderReceipt(); renderJevNote(); renderCall();
}
const SRC={get ai(){return (live()||S.recorded)&&S.jevRead?"AI read this":"pre-read"},rule:"house rule",you:"your input"};
function rdata(id){ const R=S.R; return {R,p:R.byId[id],net:R.net[id],outs:R.tx.filter(t=>t.from===id),ins:R.tx.filter(t=>t.to===id),lines:R.lines[id]}; }
function renderReceipt(){
  const {R,p,net,outs,ins,lines}=rdata(S.focus);
  const verdict=outs.length?outs.map(t=>`Pay <b>${money(t.c)}</b> to ${esc(R.byId[t.to].name)} by ${fmtDate(R.due)}.`).join("<br>")
    :ins.length?ins.map(t=>`${esc(R.byId[t.from].name)} pays you <b>${money(t.c)}</b> by ${fmtDate(R.due)}.`).join("<br>"):S.exempt.has(p.id)?"The group covers your share this time. Nothing to pay.":"You're even. Nothing to pay.";
  $("receipt").innerHTML=`<div class="rh"><b>${esc(p.name)}</b><span>${esc(S.label)} · ${fmtDate(R.start)}</span></div>
   <div class="lines">${lines.map(l=>`<div class="line"><div>${esc(l.t)}</div><div class="v">${money(l.c)}</div><div class="why">${l.src?`<span class="src src-${l.src}">${SRC[l.src]}</span>`:""}${esc(l.why)}</div></div>`).join("")}</div>
   <div class="total"><span>${net<0?"You owe":net>0?"You get back":"Balance"}</span><span class="v">${money(Math.abs(net))}</span></div>
   <div class="verdict">${verdict}</div>
   <div class="key"><span class="src src-ai">${SRC.ai}</span> ${(live()||S.recorded)&&S.jevRead?"aityx read it in the group chat":"read ahead for this sample; connect a key and aityx reads it live"}<br><span class="src src-rule">${SRC.rule}</span> your house rules, same math every time${lines.some(l=>l.src==="you")?`<br><span class="src src-you">${SRC.you}</span> you entered or changed it`:""}</div>
   <div class="stamp">receipt by aityx · ${THEMES[SAMPLES[S.key].trip].stamp}</div>`;
}
function receiptText(id){
  const {R,p,net,outs,ins,lines}=rdata(id);
  return [`${p.name}, ${S.label}`,...lines.map(l=>`${l.t}: ${money(l.c)} (${l.why})`),
    `${net<0?"You owe":net>0?"You get back":"Balance"}: ${money(Math.abs(net))}`,
    ...outs.map(t=>`Pay ${money(t.c)} to ${R.byId[t.to].name} by ${fmtDate(R.due)}`),
    ...ins.map(t=>`${R.byId[t.from].name} pays you ${money(t.c)} by ${fmtDate(R.due)}`)].join("\n");
}

function receiptCanvas(id){
  const {R,p,net,outs,ins,lines}=rdata(id), cs=getComputedStyle(document.documentElement);
  const v=n=>cs.getPropertyValue(n).trim();
  const paper=v("--paper")||"#F4F1EA", ink=v("--paper-ink")||"#1E1C21", muted=v("--paper-muted")||"#6E6A74", acc=v("--acc")||"#E36742";
  const W=440, P=26, sc=2, F="'Red Hat Mono', ui-monospace, monospace";
  const c=document.createElement("canvas"), x=c.getContext("2d");
  const wrap=(t,font,max)=>{ x.font=font; const out=[]; let cur=""; t.split(" ").forEach(w=>{ const n=cur?cur+" "+w:w; if(x.measureText(n).width>max&&cur){out.push(cur);cur=w;} else cur=n; }); if(cur) out.push(cur); return out; };
  const ops=[]; let y=P;
  const text=(t,font,color,opt={})=>{ ops.push({t,font,color,y,...opt}); };
  text(p.name,`700 20px ${F}`,ink); y+=24;
  text(`${S.label} · ${fmtDate(R.start)}`,`400 12.5px ${F}`,muted); y+=22;
  ops.push({rule:true,y}); y+=18;
  lines.forEach(l=>{
    const tl=wrap(l.t,`500 14px ${F}`,W-2*P-110);
    tl.forEach((s,i)=>{ text(s,`500 14px ${F}`,ink); if(i===0) text(money(l.c),`600 14px ${F}`,ink,{right:true}); y+=19; });
    let pw=0; if(l.src){ x.font=`600 10px ${F}`; pw=x.measureText(SRC[l.src]).width+12; ops.push({pill:SRC[l.src],src:l.src,y,x:P,w:pw}); pw+=6; }
    wrap(l.why,`400 12px ${F}`,W-2*P-pw).forEach((s,i)=>{ text(s,`400 12px ${F}`,muted,{x:P+(i?0:pw)}); y+=16; });
    y+=10;
  });
  ops.push({rule:true,y}); y+=24;
  text(net<0?"You owe":net>0?"You get back":"Balance",`700 16px ${F}`,ink); text(money(Math.abs(net)),`700 18px ${F}`,acc,{right:true}); y+=28;
  const verd=outs.length?outs.map(t=>`Pay ${money(t.c)} to ${R.byId[t.to].name} by ${fmtDate(R.due)}.`)
    :ins.length?ins.map(t=>`${R.byId[t.from].name} pays you ${money(t.c)} by ${fmtDate(R.due)}.`):["You're even. Nothing to pay."];
  verd.forEach(s=>wrap(s,`500 13.5px ${F}`,W-2*P).forEach(q=>{ text(q,`500 13.5px ${F}`,ink); y+=19; }));
  y+=10; const keys=[["ai",(live()||S.recorded)&&S.jevRead?"aityx read it in the group chat":"read ahead for this sample; connect a key and aityx reads it live"],["rule","your house rules, same math every time"]].concat(lines.some(l=>l.src==="you")?[["you","you changed it"]]:[]);
  keys.forEach(([k,t])=>{ x.font=`600 10px ${F}`; const w=x.measureText(SRC[k]).width+12; ops.push({pill:SRC[k],src:k,y,x:P,w}); text(t,`400 11.5px ${F}`,muted,{x:P+w+6}); y+=20; });
  y+=8; text(`receipt by aityx · ${THEMES[SAMPLES[S.key].trip].stamp}`,`400 11px ${F}`,muted,{center:true}); y+=P+10;
  const H=y; c.width=W*sc; c.height=H*sc; x.scale(sc,sc);
  x.fillStyle=paper; x.beginPath(); x.moveTo(0,0); x.lineTo(W,0); x.lineTo(W,H-8);
  for(let i=W;i>0;i-=10){ x.lineTo(i-5,H); x.lineTo(i-10,H-8); } x.closePath(); x.fill();
  x.textBaseline="top";
  ops.forEach(o=>{
    if(o.pill){ const C={ai:["#FBE1D8","#A8401F"],rule:["#E4E1DA","#4F4B55"],you:["#D9EFE5","#2F6B52"]}[o.src]; x.fillStyle=C[0]; x.beginPath(); x.roundRect(o.x,o.y,o.w,15,7.5); x.fill(); x.font=`600 10px ${F}`; x.fillStyle=C[1]; x.textAlign="left"; x.fillText(o.pill,o.x+6,o.y+2.5); return; }
    if(o.rule){ x.strokeStyle=muted; x.setLineDash([4,4]); x.lineWidth=1; x.beginPath(); x.moveTo(P,o.y); x.lineTo(W-P,o.y); x.stroke(); x.setLineDash([]); return; }
    x.font=o.font; x.fillStyle=o.color; x.textAlign=o.right?"right":o.center?"center":"left";
    x.fillText(o.t,o.right?W-P:o.center?W/2:(o.x??P),o.y);
  });
  return c;
}
async function copyReceiptImage(){
  try{ await document.fonts.ready; }catch(_){}
  const c=receiptCanvas(S.focus), name=`receipt-${S.R.byId[S.focus].name.toLowerCase().replace(/\W+/g,"-")}.png`;
  const blob=new Promise(r=>c.toBlob(r,"image/png"));
  try{ await navigator.clipboard.write([new ClipboardItem({"image/png":blob})]); toast("Receipt image copied"); return; }catch(e){}
  let dl=null; try{ dl=window.claude?.use?await window.claude.use("downloads"):null; }catch(_){}
  if(dl){ try{ await dl.save({filename:name,data:await blob}); toast("Receipt image saved"); }catch(e){ if(e?.code!=="declined") copy(receiptText(S.focus)); } return; }
  try{ const a=document.createElement("a"); a.href=URL.createObjectURL(await blob); a.download=name; document.body.appendChild(a); a.click(); a.remove(); toast("Receipt image saved"); }
  catch(e){ copy(receiptText(S.focus)); }
}

const HOT=new Set(["message","answers","exempt_ids","transfers","pay_by","owes","evidence_threshold"]);
function hl(o){ return esc(JSON.stringify(o,null,2))
  .replace(/&quot;([^&]*?)&quot;(\s*:)/g,(m,k,c)=>`<span class="k${HOT.has(k)?" hot":""}">"${k}"</span>${c}`)
  .replace(/: &quot;(.*?)&quot;/g,': <span class="s">"$1"</span>')
  .replace(/(<span class="k">"noul"<\/span>: )([0-9.]+)/g,(m,a,v)=>+v>=0.5?a+`<span class="hot">${v}</span>`:m); }
let VIEW="key";
const pct=v=>Math.round(v*100)+"%";
function readAnswers(){ if(live()) return S.jevRead&&LIVE.read&&LIVE.read.res&&LIVE.read.res.answers; return S.recorded&&S.recorded.read&&S.recorded.read.res&&S.recorded.read.res.answers; }
// Plain words for what Jev read about who pays. The cut-off itself lives in the decision (evidence_threshold).
function renderJevNote(){
  const n=$("jevnote"), a=readAnswers(); if(!a){ n.hidden=true; return; }
  const bar=pct(EVIDENCE);
  const rows=S.people.filter(p=>!isKid(p)).map(p=>({p,v:a[`${p.id}_not_paying`]&&a[`${p.id}_not_paying`].noul})).filter(x=>typeof x.v==="number"&&x.v>=EVIDENCE);
  if(!rows.length&&!S.exemptByYou){ n.hidden=true; return; }
  n.hidden=false;
  n.innerHTML=rows.map(({p,v})=>`<span>Jev read <b>${pct(v)}</b> that ${esc(p.name)} isn't paying. That clears the rules' ${bar} bar, so ${esc(p.name)} sits out and the others cover the share.</span>`).join("")
    +(S.exemptByYou?`<span>You changed who pays in the house rules, so your choice counts.</span>`:"");
  if(S.exemptByYou&&!rows.length) n.innerHTML=`<span>You changed who pays in the house rules, so your choice counts.</span>`;
}
const RULE_KEYS=["free_age","half_age","split_by_nights","drinkers_split_drinks","pay_days_before","evidence_threshold"];
function slimReadReq(r){ return r&&{questions:Object.fromEntries(Object.entries(r.questions||{}).map(([k,q])=>[k,q.instructions])),state:r.state}; }
function slimReadRes(r){ return r&&(r.answers?{answers:Object.fromEntries(Object.entries(r.answers).map(([k,a])=>[k,{noul:a&&a.noul}])),usage:r.usage}:r); }
function slimSettleReq(r){ if(!r||!r.decision) return r; const d=r.decision, all=Object.keys(d.decisions||{});
  return {decision:{name:d.name,house_rules:Object.fromEntries(RULE_KEYS.filter(k=>d.decisions[k]).map(k=>[k,d.decisions[k].expr])),
    more:`${all.length-RULE_KEYS.length} more decisions and ${Object.keys(d.functions||{}).length} functions do the math. See Full JSON.`},state:r.state}; }
function slimSettleRes(r){ if(!r||!r.answers) return r; const a=r.answers, val=x=>x&&("value" in x?x.value:"date" in x?x.date:"number" in x?x.number:x.noul);
  const out={answers:{}}; ["exempt_ids","transfers","pay_by"].forEach(k=>{ if(k in a) out.answers[k]=val(a[k]); });
  const rc=a.receipts&&a.receipts.value; if(rc) out.answers.receipts=rc.filter(x=>x.id===S.focus);
  if(r.decision_error) out.decision_error=r.decision_error; return out; }
function renderGist(read,settle){
  const g=$("gist"), ra=read&&read.res&&read.res.answers, sr=settle&&settle.res, sa=sr&&sr.answers;
  if(!ra&&!sr){ g.hidden=true; return; } g.hidden=false;
  const nm=id=>(S.R.byId[id]||{name:id}).name; let h="";
  if(ra){ const rows=Object.entries(ra).map(([q,x])=>[q,x&&x.noul]).filter(([,v])=>typeof v==="number").sort((x,y)=>y[1]-x[1]);
    const shown=rows.filter(([,v])=>v>=0.15), rest=rows.length-shown.length;
    h+=`<h4>Step 1 · Jev read the message (AI)</h4><ul>${shown.map(([q,v])=>`<li><code>${esc(q)}</code><span class="pct${v>=EVIDENCE?" hit":""}">${pct(v)} ${v>=EVIDENCE?"· counts":"· under "+pct(EVIDENCE)+", doesn't count"}</span></li>`).join("")}${rest?`<li class="soft">${rest} more questions read under 15%, so they don't count</li>`:""}</ul>`; }
  if(sr){ h+=`<h4>Step 2 · The rules settled it (no AI)</h4>`;
    if(sr.decision_error) h+=`<ul><li class="soft">decision_error: ${esc(sr.decision_error.message||sr.decision_error.code||"")}</li></ul>`;
    else if(sa){ const ex=sa.exempt_ids&&sa.exempt_ids.value, tx=(sa.transfers&&sa.transfers.value)||[], due=sa.pay_by&&sa.pay_by.date;
      h+=`<ul><li><code>exempt_ids</code><span>${ex&&ex.length?esc(list(ex.map(nm))):"nobody, everyone pays"}</span></li>
      <li><code>pay_by</code><span>${esc(due||"")}</span></li>
      <li><code>transfers</code><span>${tx.length?tx.map(t=>`${esc(nm(t.from))} → ${esc(nm(t.to))} <span class="pct hit">$${Number(t.amount).toFixed(2)}</span>`).join("<br>"):"nobody owes anything"}</span></li></ul>`; } }
  g.innerHTML=h;
}
function showCall(read,settle,head,status){
  const k=VIEW==="key", two=(a,b)=>a&&b?{"1_jev_reads_the_message":a,"2_rules_settle":b}:(a||b||{});
  const q1=read&&(k?slimReadReq(read.req):read.req), q2=settle&&(k?slimSettleReq(settle.req):settle.req);
  const r1=read&&(k?slimReadRes(read.res):read.res), r2=settle&&(k?slimSettleRes(settle.res):settle.res);
  $("req").innerHTML=`<span class="c">${esc(head)}${k?"\n// Key parts. Switch to Full JSON for everything.":""}</span>\n`+hl(two(q1,q2));
  $("res").innerHTML=(status?`<span class="c">// HTTP ${esc(status)}</span>\n`:"")+(k&&r2&&r2.answers&&r2.answers.receipts?`<span class="c">// receipts: only ${esc((S.R.byId[S.focus]||{}).name||"")}'s here</span>\n`:"")+hl(two(r1,r2));
}
function renderCall(){
  if(live()&&(LIVE.call||LIVE.read)){
    showCall(S.jevRead?LIVE.read:null,LIVE.call,`// POST ${aityx.endpoint()}\n// ${aityx.whose()}: the key never reaches this page`,(LIVE.call||LIVE.read).status);
    return;
  }
  if(!live()){
    const rec=S.recorded;
    if(rec) showCall(rec.read,rec.settle,`// recorded ${rec.when} · POST /v1/systemone, twice`,"");
    else {
      $("req").innerHTML=`<span class="c">// Connect a key above to see the real request.</span>`;
      $("res").innerHTML=`<span class="c">// Nothing runs without aityx.</span>`;
    }
    return;
  }
  const R=S.R,r=S.rules;
  const req={model:"jev-latest",
    questions:Object.assign(Object.fromEntries(S.people.filter(canDrink).map(p=>[`${p.id}_drinks`,{type:"noul",ask:`Does the message say ${p.name} drinks?`}])),{not_paying:{type:"choice",ask:"Who does the message say won't pay?"}}),
    state:{start:S.start,people:S.people.map(p=>({id:p.id,age:p.age,nights:p.nights,...(p.guardians.length?{with:p.guardians}:{})})),expenses:S.expenses.map(e=>({kind:e.kind,amount:e.amount,paid_by:e.by}))},
    decision:{decisions:{
      weight:{table:[`age <= ${r.freeAge} => 0  # kids stay free`,`age <= ${r.halfAge} => 0.5  # kids pay half`,"otherwise => 1"]},
      share:{expr:r.byNights?"amount * weight * nights / sum(weight * nights)":"amount * weight / sum(weight)"},
      drinks_split:{expr:r.drinksOnly?"adults where drinks":"adults"},
      pay_by:{expr:`start - ${r.dueDays} days`},
      transfers:{expr:"settle(paid - owed)"}}}};
  const res={answers:{pay_by:{date:R.due.toISOString().slice(0,10)},transfers:{value:R.tx.map(t=>({from:t.from,to:t.to,amount:+(t.c/100).toFixed(2)}))}},
    receipt:{provenance:Object.assign(Object.fromEntries(S.people.filter(canDrink).map(p=>[`${p.id}_drinks`,p.edited.drinks?"state":"jev"])),{not_paying:S.exemptByYou?"state":"jev",nights:"state",expenses:"state",start:"state"})},
    usage:{input_tokens:"…"}};
  $("req").innerHTML=`<span class="c">// POST /v1/systemone (illustrative)</span>\n`+hl(req);
  $("res").innerHTML=hl(res);
}

let toastT;
function toast(m){ let t=document.querySelector(".toast"); if(!t){t=document.createElement("div");t.className="toast";t.setAttribute("role","status");document.body.appendChild(t);} t.textContent=m; t.hidden=false; clearTimeout(toastT); toastT=setTimeout(()=>t.hidden=true,1800); }
async function copy(txt){ try{ await navigator.clipboard.writeText(txt); toast("Copied"); }catch(e){ const ta=document.createElement("textarea"); ta.value=txt; document.body.appendChild(ta); ta.select(); try{document.execCommand("copy");toast("Copied");}catch(_){toast("Select and copy the text");} ta.remove(); } }

function menu(open){ const m=$("fill-menu"); if(!m) return; m.hidden=!open; $("fill-more").setAttribute("aria-expanded",String(open)); if(open) m.querySelector("button").focus(); }
// Like "Fill random" on the aityx demos, per holiday: another story from the holiday in the tab; the menu lists that holiday's stories by result.
function fillCase(trip){ trip=trip||SAMPLES[S.key].trip; const ks=Object.keys(SAMPLES).filter(k=>k!==S.key&&SAMPLES[k].trip===trip); load(ks[Math.random()*ks.length|0]);
  toast(`${S.label}. Press Split it.`); }
$("fill-random").innerHTML=`${ICON.dice}<span>Fill random</span>`; $("fill-more").innerHTML=ICON.caret;

document.addEventListener("keydown",e=>{ if(e.key==="Escape"&&!$("fill-menu").hidden){ menu(false); $("fill-more").focus(); } });
document.addEventListener("click",e=>{
  if(!e.target.closest("#fill")) menu(false);
  const b=e.target.closest("button"); if(!b) return;
  if(b.id==="fill-more"){ menu($("fill-menu").hidden); return; }
  if(b.id==="fill-random"){ fillCase(); return; }
  if(b.dataset.pick){ menu(false); if(b.dataset.pick!==S.key) load(b.dataset.pick); return; }
  if(b.dataset.view){ VIEW=b.dataset.view; b.parentElement.querySelectorAll("button").forEach(x=>x.setAttribute("aria-pressed",x===b)); renderCall(); renderDecisionView(); return; }
  if(b.dataset.k){ load(b.dataset.k); return; }
  if(b.dataset.w){ S.focus=b.dataset.w; render(false); return; }
  if(b.dataset.seg){ const on=b.dataset.v==="1"; if(b.dataset.seg==="nights") S.rules.byNights=on; else S.rules.drinksOnly=on;
    b.parentElement.querySelectorAll("button").forEach(x=>x.setAttribute("aria-pressed",x===b)); run(); return; }
  if(b.dataset.x){ const id=b.dataset.x; S.exempt.has(id)?S.exempt.delete(id):S.exempt.add(id); S.exemptByYou=true;
    b.setAttribute("aria-pressed",S.exempt.has(id)); const n=$("nudge"); if(n) n.remove(); S.focus=id; run(); return; }
  if(b.id==="go"){ document.body.classList.remove("pending"); if(live()){ run(); readLive(); } else showRecorded(); $("result").scrollIntoView({behavior:matchMedia("(prefers-reduced-motion: reduce)").matches?"auto":"smooth",block:"start"}); return; }
  if(b.id==="recall"){ recordAll(); return; }
  if(b.id==="readchat"){ readChat(); return; }
  if(b.id==="add-adult"||b.id==="add-kid"){ const kid=b.id==="add-kid", adults=S.people.filter(p=>!isKid(p)); S.n++;
    S.people.push({id:`new${S.n}`,name:kid?`Kid ${S.n}`:`Guest ${S.n}`,age:kid?8:null,nights:Math.max(...S.people.map(p=>p.nights)),drinks:!kid,guardians:kid?[adults[0].id]:[],edited:{}});
    listChanged(); const i=$("ppl").querySelectorAll("input[type=text]"); i[i.length-1].select(); return; }
  if(b.id==="add-exp"){ S.expenses.push({kind:"other",what:"New expense",amount:0,by:S.people.find(p=>!isKid(p)).id,edited:true}); listChanged();
    const i=$("exp").querySelectorAll("input[type=text]"); i[i.length-1].select(); return; }
  if(b.dataset.delp){ const id=b.dataset.delp, adults=S.people.filter(p=>!isKid(p));
    if(S.expenses.some(e=>e.by===id)||S.people.some(k=>k.guardians.includes(id))){ toast("They paid for something or bring a kid. Change that first."); return; }
    if(adults.length<2&&adults[0].id===id){ toast("Someone has to come."); return; }
    S.people=S.people.filter(p=>p.id!==id); S.exempt.delete(id); listChanged(); return; }
  if(b.dataset.dele){ if(S.expenses.length<2) return; S.expenses.splice(+b.dataset.dele,1); listChanged(); return; }
  if(b.id==="rec"&&LIVE.rec){ copy(JSON.stringify({[LIVE.rec.key]:LIVE.rec})); return; }
  if(b.id==="copyall"){ const R=S.R; copy(`${S.label}: who pays whom, by ${fmtDate(R.due)}\n`+R.tx.map(t=>`${R.byId[t.from].name} pays ${R.byId[t.to].name} ${money(t.c)}`).join("\n")+"\nSplit with aityx"); return; }
  if(b.id==="copyone"){ copyReceiptImage(); return; }
});
document.addEventListener("change",e=>{
  const t=e.target;
  if(t.dataset.p&&(t.dataset.f==="name"||t.dataset.f==="guardian")){ const p=S.people.find(x=>x.id===t.dataset.p);
    if(t.dataset.f==="name") p.name=t.value.trim()||"Someone"; else p.guardians=[t.value]; listChanged(); return; }
  if(t.dataset.ef){ const ex=S.expenses[+t.dataset.e]; ex[t.dataset.ef]=t.dataset.ef==="what"?(t.value.trim()||"Expense"):t.value; ex.edited=true; listChanged(); }
});
document.addEventListener("input",e=>{
  const t=e.target, r=S.rules, num=()=>parseInt(t.value,10);
  if(t.dataset.f==="name"||t.dataset.f==="guardian"||t.dataset.ef) return;
  if(t.id==="msg"){ if(live()){ readerNote("Chat changed. Read it to update the lists below, then Jev reads it and aityx settles.","warn"); $("readchat").classList.add("go"); } else setNote(true); return; }
  if(t.dataset.p){ const p=S.people.find(x=>x.id===t.dataset.p), f=t.dataset.f;
    if(f==="drinks") p.drinks=t.checked; else { const v=num(); if(isNaN(v)) return; p[f]=f==="nights"?Math.max(1,v):Math.max(0,v); }
    if(!p.edited[f]){ p.edited[f]=true; t.insertAdjacentHTML("afterend",`<span class="edited">changed</span>`); } run(); return; }
  if(t.dataset.e){ const ex=S.expenses[+t.dataset.e], v=parseFloat(t.value); if(isNaN(v)) return; ex.amount=Math.max(0,v);
    if(!ex.edited){ ex.edited=true; t.insertAdjacentHTML("afterend",`<span class="edited">changed</span>`); } run(); return; }
  if(t.id==="r-free"){ const v=num(); if(!isNaN(v)){ r.freeAge=v; run(); } }
  if(t.id==="r-half"){ const v=num(); if(!isNaN(v)){ r.halfAge=v; run(); } }
  if(t.id==="r-due"){ const v=num(); if(!isNaN(v)){ r.dueDays=Math.max(0,v); run(); } }
});
function stockingSVG(i){
  const cols=["#C8262E","#2E7D4F","#C8262E","#1F5F8B","#B8862B","#2E7D4F","#C8262E","#7A3E9D"], c=cols[i%cols.length];
  return `<svg viewBox="0 0 44 62" aria-hidden="true"><path d="M10 12h22v24c0 6-3 9-8 12l-10 6c-6 3-12 0-12-6 0-4 3-7 7-8l1-1z" fill="${c}"/><path d="M12 20h18M12 28h18" stroke="rgba(255,255,255,.25)" stroke-width="2" stroke-dasharray="3 3"/><rect x="7" y="3" width="28" height="11" rx="4" fill="#F6F0E6"/><circle cx="21" cy="3" r="2.4" fill="#F4C15A"/></svg>`;
}
function countdown(th){
  const now=new Date(), t=new Date(th.target+"T00:00:00"), d=Math.ceil((t-now)/864e5);
  $("countdown").innerHTML=d>0?`<b>${d}</b> days ${th.until}`:d===0?`<b>Today!</b>`:"";
}
const NS="http://www.w3.org/2000/svg";
function buildGarland(){
  const W=innerWidth, n=Math.max(8,Math.round(W/70)), seg=W/n; let path=`M0 6`, bulbs="";
  const cols=["#FF5A4E","#F4C15A","#4FD18B","#5AB4FF","#FF9AD5"];
  for(let i=0;i<n;i++){ const x0=i*seg, x1=x0+seg; path+=` Q${x0+seg/2} 46 ${x1} 6`;
    for(let k=1;k<=3;k++){ const t=k/4, x=x0+seg*t, y=(1-t)*(1-t)*6+2*(1-t)*t*46+t*t*6;
      bulbs+=`<g class="bulb" style="animation-delay:${((i*3+k)%7)*.35}s"><circle cx="${x}" cy="${y+5}" r="9" fill="${cols[(i*3+k)%5]}" opacity=".25"/><circle cx="${x}" cy="${y+5}" r="4" fill="${cols[(i*3+k)%5]}"/></g>`; } }
  $("garland").innerHTML=`<svg viewBox="0 0 ${W} 64" preserveAspectRatio="none"><path d="${path}" fill="none" stroke="#2F5E3A" stroke-width="5" stroke-linecap="round"/><path d="${path}" fill="none" stroke="#3E7A4B" stroke-width="2" stroke-dasharray="4 6"/>${bulbs}</svg>`;
}
function buildTree(){
  const cols=["#FF5A4E","#F4C15A","#4FD18B","#5AB4FF","#FFFFFF"]; let lights="";
  const tiers=[[95,40,40,110],[95,80,25,165],[95,125,10,225]];
  for(let i=0;i<34;i++){ const tr=tiers[i%3], y=tr[1]+20+Math.random()*(tr[3]-tr[1]-30), half=(y-tr[1])/(tr[3]-tr[1])*(95-tr[2]);
    const x=95+(Math.random()*2-1)*half*.85; lights+=`<circle class="bulb" style="animation-delay:${(i%9)*.3}s" cx="${x}" cy="${y}" r="3" fill="${cols[i%5]}"/>`; }
  $("tree").innerHTML=`<svg viewBox="0 0 190 280" aria-hidden="true"><rect x="84" y="225" width="22" height="30" fill="#4A2A18"/>
   <polygon points="95,40 160,110 30,110" fill="#1F5232"/><polygon points="95,80 175,165 15,165" fill="#22603A"/><polygon points="95,125 185,225 5,225" fill="#256B40"/>
   ${lights}<polygon points="95,14 101,30 118,30 104,40 109,56 95,46 81,56 86,40 72,30 89,30" fill="#F4C15A"/>
   <rect x="22" y="236" width="38" height="30" fill="#C8262E"/><rect x="38" y="236" width="6" height="30" fill="#F4C15A"/><rect x="128" y="242" width="44" height="24" fill="#2E7D4F"/><rect x="146" y="242" width="6" height="24" fill="#F4C15A"/></svg>`;
}
function buildSkyline(){
  const W=innerWidth, H=150; let b="", x=0, wins="";
  const towerX=Math.round(W*0.22);
  while(x<W){ const w=30+Math.random()*60, h=40+Math.random()*80;
    if(Math.abs(x-towerX)<70){ x+=w; continue; }
    b+=`<rect x="${x}" y="${H-h}" width="${w+1}" height="${h}" fill="#0A0510"/>`;
    for(let wy=H-h+8; wy<H-6; wy+=12) for(let wx=x+6; wx<x+w-8; wx+=10) if(Math.random()<.22) wins+=`<rect x="${wx}" y="${wy}" width="4" height="6" fill="#F7C96A" opacity="${.5+Math.random()*.5}"/>`;
    x+=w; }
  const t=towerX; const tower=`<rect x="${t-18}" y="${H-120}" width="36" height="120" fill="#0A0510"/><polygon points="${t-22},${H-120} ${t+22},${H-120} ${t},${H-150}" fill="#0A0510"/>
    <circle cx="${t}" cy="${H-98}" r="12" fill="#F4E3B0"/><line x1="${t}" y1="${H-98}" x2="${t}" y2="${H-108}" stroke="#0A0510" stroke-width="2"/><line x1="${t}" y1="${H-98}" x2="${t}" y2="${H-105}" stroke="#0A0510" stroke-width="2.5"/>`;
  $("skyline").innerHTML=`<svg viewBox="0 0 ${W} ${H}" preserveAspectRatio="none"><defs><linearGradient id="sg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#120A1C" stop-opacity="0"/><stop offset="1" stop-color="#120A1C"/></linearGradient></defs>${b}${wins}${tower}<rect x="0" y="${H-20}" width="${W}" height="20" fill="url(#sg)"/></svg>`;
}
function buildCorners(){
  const leaf="M12 2l1.5 4 3-1.5-1 4 3.5-.5-2 3 3 1.5-4 1 1 3-4-1.5L12 22l-1-6.5-4 1.5 1-3-4-1 3-1.5-2-3 3.5.5-1-4 3 1.5z";
  const oval="M12 2C17 7 17 17 12 22 7 17 7 7 12 2z";
  const cols=["#D9541E","#E8892B","#B8361C","#E2A33A","#8E3A1C","#9BA33A"];
  const spots=[[10,8,58,-20,0],[70,4,40,25,1],[4,70,46,95,1],[52,46,34,60,0],[118,10,30,-50,1],[10,128,32,140,0],[96,40,24,10,1]];
  let g=spots.map((p,i)=>`<path d="${p[4]?leaf:oval}" fill="${cols[i%cols.length]}" transform="translate(${p[0]} ${p[1]}) scale(${p[2]/24}) rotate(${p[3]} 12 12)"/>`).join("");
  g+=`<g fill="#B3202A"><circle cx="66" cy="62" r="6"/><circle cx="76" cy="58" r="5"/><circle cx="72" cy="70" r="5"/></g><path d="M0 0 Q60 40 150 30" stroke="#7A4A2A" stroke-width="3" fill="none"/>`;
  ["c-tl","c-tr","c-bl","c-br"].forEach(id=>$(id).innerHTML=`<svg viewBox="0 0 170 170" aria-hidden="true">${g}</svg>`);
}
function buildDecor(){ buildGarland(); buildTree(); buildSkyline(); buildCorners(); }
buildDecor(); let rT; addEventListener("resize",()=>{ clearTimeout(rT); rT=setTimeout(()=>{buildGarland();buildSkyline();},200); });

// Ambient layer: warm bokeh for Christmas, fireworks for New Year's, leaves for Thanksgiving
const FX=(function(){
  const cv=$("fx"), ctx=cv.getContext("2d"), reduce=matchMedia("(prefers-reduced-motion: reduce)").matches;
  let kind="christmas", parts=[], rockets=[], W=0, H=0, raf=0, tick=0;
  const FW=["#FF5FA8","#FFFFFF","#F2C14E","#FF3D6E","#C38BFF","#FFB3D9"], LEAF=["#D9541E","#E8892B","#B8361C","#E2A33A","#8E3A1C"];
  const leafPath=new Path2D("M12 2l1.5 4 3-1.5-1 4 3.5-.5-2 3 3 1.5-4 1 1 3-4-1.5L12 22l-1-6.5-4 1.5 1-3-4-1 3-1.5-2-3 3.5.5-1-4 3 1.5z");
  function size(){ const d=Math.min(2,devicePixelRatio||1); W=innerWidth; H=innerHeight; cv.width=W*d; cv.height=H*d; ctx.setTransform(d,0,0,d,0,0); }
  function ambient(randY){
    const p={x:Math.random()*W,y:randY?Math.random()*H:-24,r:Math.random()*6.28,vr:(Math.random()-.5)*.05,t:Math.random()*500};
    if(kind==="christmas"){ p.y=randY?Math.random()*H:H+20; p.s=3+Math.random()*9; p.vy=-(.08+Math.random()*.25); p.vx=0; p.c=["255,190,90","255,120,70","255,230,170"][Math.random()*3|0]; }
    else { p.s=10+Math.random()*10; p.vy=.5+Math.random()*.7; p.vx=(Math.random()-.5)*.4; p.c=LEAF[Math.random()*5|0]; p.a=.7+Math.random()*.3; }
    return p;
  }
  function burst(x,y){ const c=FW[Math.random()*FW.length|0], c2=FW[Math.random()*FW.length|0], n=70+Math.random()*40|0, sp=2+Math.random()*2.5;
    for(let i=0;i<n;i++){ const a=i/n*6.283+Math.random()*.1, v=sp*(.5+Math.random()*.6); parts.push({x,y,vx:Math.cos(a)*v,vy:Math.sin(a)*v,life:1,decay:.008+Math.random()*.01,c:Math.random()<.7?c:c2,s:1.2+Math.random()*1.4}); } }
  function launch(){ rockets.push({x:W*(.15+Math.random()*.7),y:H,vy:-(7+Math.random()*3.5),vx:(Math.random()-.5)*1.2,ty:H*(.12+Math.random()*.35)}); }
  function frame(){
    tick++;
    if(kind==="newyear"){
      ctx.globalCompositeOperation="destination-out"; ctx.fillStyle="rgba(0,0,0,.16)"; ctx.fillRect(0,0,W,H); ctx.globalCompositeOperation="lighter";
      if(tick%38===0||(tick%17===0&&Math.random()<.35)) launch();
      for(const r of rockets){ r.x+=r.vx; r.y+=r.vy; r.vy+=.06; ctx.fillStyle="rgba(255,220,170,.9)"; ctx.fillRect(r.x,r.y,2,5); if(r.y<=r.ty||r.vy>=0){ burst(r.x,r.y); r.dead=1; } }
      rockets=rockets.filter(r=>!r.dead);
      for(const p of parts){ p.x+=p.vx; p.y+=p.vy; p.vx*=.985; p.vy=p.vy*.985+.035; p.life-=p.decay; ctx.globalAlpha=Math.max(0,p.life); ctx.fillStyle=p.c; ctx.beginPath(); ctx.arc(p.x,p.y,p.s,0,6.283); ctx.fill(); }
      parts=parts.filter(p=>p.life>0); ctx.globalAlpha=1; ctx.globalCompositeOperation="source-over";
    } else {
      ctx.clearRect(0,0,W,H);
      for(const p of parts){ p.t++; p.r+=p.vr; p.y+=p.vy; p.x+=p.vx+Math.sin(p.t*.02+p.s)*.4;
        if(p.y>H+30||p.y<-30) Object.assign(p,ambient(false));
        ctx.save(); ctx.translate(p.x,p.y);
        if(kind==="christmas"){ const tw=.25+.25*Math.sin(p.t*.03); const g=ctx.createRadialGradient(0,0,0,0,0,p.s); g.addColorStop(0,`rgba(${p.c},${tw+.15})`); g.addColorStop(1,`rgba(${p.c},0)`); ctx.fillStyle=g; ctx.beginPath(); ctx.arc(0,0,p.s,0,6.283); ctx.fill(); }
        else { ctx.rotate(p.r); ctx.globalAlpha=p.a; ctx.scale(p.s/24,p.s/24); ctx.translate(-12,-12); ctx.fillStyle=p.c; ctx.fill(leafPath); }
        ctx.restore(); }
    }
    if(!reduce) raf=requestAnimationFrame(frame);
  }
  function set(k){ kind=k; size(); cancelAnimationFrame(raf); rockets=[]; ctx.clearRect(0,0,W,H);
    if(k==="newyear"){ parts=[]; if(reduce){ for(let i=0;i<4;i++){ burst(W*(.2+i*.2),H*(.2+(i%2)*.15)); } for(let i=0;i<40;i++) { for(const p of parts){p.x+=p.vx;p.y+=p.vy;p.vy+=.03;} } ctx.globalCompositeOperation="lighter"; for(const p of parts){ctx.fillStyle=p.c;ctx.beginPath();ctx.arc(p.x,p.y,p.s,0,6.283);ctx.fill();} ctx.globalCompositeOperation="source-over"; return; } launch(); }
    else parts=Array.from({length:Math.round(Math.min(k==="christmas"?40:22,W*H/(k==="christmas"?22000:40000)))},()=>ambient(true));
    frame(); }
  addEventListener("resize",()=>set(kind));
  document.addEventListener("visibilitychange",()=>{ if(reduce) return; cancelAnimationFrame(raf); if(!document.hidden) frame(); });
  return {set};
})();
load("thanks");
