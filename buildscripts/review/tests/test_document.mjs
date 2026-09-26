import assert from 'node:assert/strict';
import vm from 'node:vm';
import fs from 'node:fs';
const source = new URL('../../../src/notationscene/qml/MuseScore/NotationScene/ReviewDocument.js', import.meta.url);
const r = vm.createContext({}); vm.runInContext(fs.readFileSync(source, 'utf8'), r);
const g = {valid:true,anchor:{measure:'M2',staff:'S1',beat:'1/4',fraction:0.5},x:100,y:200,spatium:10};
const mark = r.makeMark('stroke',g,{x:115,y:185});mark.points.push({x:4,y:0});
const doc = r.empty('score1'); doc.marks.push(mark);
const reload = r.decode(JSON.stringify(doc),'score1');
assert.equal(reload.marks[0].anchor.measure,'M2');
// Reflow changes system/page origin. Shape and local offsets stay fixed in staff spaces.
const moved = r.projected(mark,{valid:true,x:400,y:800,spatium:10});
assert.equal(moved[0].x,415); assert.equal(moved[0].y,785);
assert.equal(moved[1].x-moved[0].x,25);
// Deleted measure: no rendering and no reassignment to a new measure with the same number.
assert.equal(r.projected(mark,{valid:false,reason:'measure-deleted'}).length,0);
assert.equal(mark.anchor.measure,'M2');
// Undo restores the same identity: projection works again without editing the annotation.
assert.equal(r.projected(mark,g)[0].x,115);
const target = {...g,anchor:{...g.anchor,measure:'M4'},x:500,y:700};
const relocated=r.relocate(mark,target,{x:520,y:725});
assert.equal(relocated.anchor.measure,'M4');assert.equal(r.projected(relocated,target)[0].x,520);
assert.equal(r.projected(relocated,target)[0].y,725);
assert.equal(relocated.points[1].x-relocated.points[0].x,2.5);
const accepted=r.acceptDrafts(doc,'archive');
accepted.marks.push(r.makeMark('text',g,{x:100,y:190},'Rivedere armonia\nseconda riga'));
assert.equal(r.discardDrafts(accepted).marks.length,1);assert.equal(r.discardDrafts(accepted).marks[0].status,'archive');
assert.equal(r.acceptDrafts(accepted,'print').marks[0].status,'archive');
assert.equal(r.acceptDrafts(accepted,'print').marks[1].status,'print');
assert.throws(()=>r.decode(JSON.stringify(doc),'other-score'));
const bad=JSON.parse(JSON.stringify(doc));bad.marks[0].points[0].x='12';assert.throws(()=>r.validate(bad,'score1'));
const dup=JSON.parse(JSON.stringify(doc));dup.marks.push(dup.marks[0]);assert.throws(()=>r.validate(dup,'score1'));
assert.throws(()=>r.decode('{bad json','score1'));
assert.equal(doc.marks.length,1);assert.equal(doc.marks[0].status,'draft');
console.log('PASS: reflow, save/load, deletion/undo, relocation, archive/print, validation');
