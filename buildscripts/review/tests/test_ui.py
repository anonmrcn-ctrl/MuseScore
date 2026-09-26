"""Run with QT_QPA_PLATFORM=offscreen python3 buildscripts/review/tests/test_ui.py.
Requires PySide6. Loads the actual QML component with a score adapter test double.
"""
import os
os.environ.setdefault('QT_QPA_PLATFORM', 'offscreen')
os.environ.setdefault('QT_QUICK_BACKEND', 'software')
from pathlib import Path
from PySide6.QtCore import QObject, Property, Signal, Slot, QPointF, QPoint, QUrl, Qt, QMetaObject
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlEngine, QQmlComponent, QJSValue
from PySide6.QtQuick import QQuickWindow
from PySide6.QtTest import QTest

class ScoreAdapter(QObject):
    reviewContextChanged = Signal()
    reviewActiveChanged = Signal()
    reviewLayoutChanged = Signal()
    matrixChanged = Signal()
    def __init__(self):
        super().__init__(); self.active=False; self.score='scoreA'; self.storage={}; self.deleted=False; self.origin=QPointF(100,200)
    @Property(str, notify=reviewContextChanged)
    def reviewScoreId(self): return self.score
    @Property(bool, notify=reviewActiveChanged)
    def reviewActive(self): return self.active
    @reviewActive.setter
    def reviewActive(self, val): self.active=val; self.reviewActiveChanged.emit()
    @Slot(result=str)
    def reviewRecoveryPath(self): return 'file:///recovery/'+self.score+'.json'
    @Slot(QUrl, str, result=bool)
    def saveReview(self, url, data): self.storage[url.toString()]=data; return True
    @Slot(QUrl, result=str)
    def loadReview(self, url): return self.storage.get(url.toString(),'')
    @Slot(QPointF, result=QPointF)
    def reviewToScore(self,p): return p
    @Slot(QPointF, result=QPointF)
    def reviewToView(self,p): return p
    @Slot(QPointF, result='QVariantMap')
    def reviewAnchorAt(self,p):
        return {'valid':True, 'anchor':{'measure':'M2' if not self.deleted else 'M3','staff':'S1','beat':'0/1','fraction':0.5}, 'x':self.origin.x(),'y':self.origin.y(),'spatium':10.0}
    @Slot('QVariantMap', result='QVariantMap')
    def reviewAnchorGeometry(self,a):
        if self.deleted and a.get('measure')=='M2': return {'valid':False,'reason':'measure-deleted'}
        return {'valid':True,'x':self.origin.x(),'y':self.origin.y(),'spatium':10.0}
    @Slot(QUrl,str,result=bool)
    def exportReviewPdf(self,u,s): return True

app=QGuiApplication([]); engine=QQmlEngine(); score=ScoreAdapter()
path=Path(__file__).resolve().parents[3]/'src/notationscene/qml/MuseScore/NotationScene/ScoreReviewOverlay.qml'
component=QQmlComponent(engine,QUrl.fromLocalFile(str(path)))
assert not component.isError(), '\n'.join(e.toString() for e in component.errors())
root=component.createWithInitialProperties({'view':score})
assert root is not None, '\n'.join(e.toString() for e in component.errors())
window=QQuickWindow(); window.resize(1100,800); root.setParentItem(window.contentItem()); root.setWidth(1100);root.setHeight(800); window.show();QTest.qWait(150)
def doc(): return root.property('document').toVariant()
def call(name,*args):
    # Invoke QML functions through JS so arrays/objects preserve their JS type.
    fn=engine.newQObject(root).property(name)
    return fn.callWithInstance(engine.newQObject(root), [engine.toScriptValue(a) for a in args])
score.reviewActive=True;QTest.qWait(50)
QTest.mousePress(window,Qt.LeftButton,Qt.NoModifier,QPoint(200,300))
QTest.mouseMove(window,QPoint(230,310),30)
QTest.mouseRelease(window,Qt.LeftButton,Qt.NoModifier,QPoint(240,315));QTest.qWait(60)
assert len(doc()['marks'])==1,doc()
assert doc()['marks'][0]['anchor']['measure']=='M2'
assert len(doc()['marks'][0]['points'])>=2
assert score.storage['file:///recovery/scoreA.json']
# Saved model remains anchored while geometry moves to another system/page.
score.origin=QPointF(400,500);score.reviewLayoutChanged.emit();QTest.qWait(30)
assert root.property('resolved').toVariant()[0]['geometry']['x']==400
score.deleted=True;score.reviewLayoutChanged.emit();QTest.qWait(30)
assert root.property('orphanCount')==1
mark_id=doc()['marks'][0]['id'];root.setProperty('relocatingId',mark_id)
QTest.mouseClick(window,Qt.LeftButton,Qt.NoModifier,QPoint(500,500));QTest.qWait(30)
assert doc()['marks'][0]['anchor']['measure']=='M3';assert root.property('orphanCount')==0
call('undo');assert doc()['marks'][0]['anchor']['measure']=='M2'
call('redo');assert doc()['marks'][0]['anchor']['measure']=='M3'
# Wrong-score import is rejected without replacing the current document.
score.storage['file:///wrong.json']='{"format":"musescore-review-2","scoreId":"other","marks":[]}'
call('importFile',QUrl('file:///wrong.json'));assert len(doc()['marks'])==1;assert root.property('error')
# Switching scores never projects A's marks on B; switching back restores A.
score.score='scoreB';score.reviewContextChanged.emit();QTest.qWait(30);assert len(doc()['marks'])==0
score.score='scoreA';score.reviewContextChanged.emit();QTest.qWait(30);assert len(doc()['marks'])==1
# Text mode opens a real in-window editor, without browser prompt().
root.setProperty('tool','text');QTest.mouseClick(window,Qt.LeftButton,Qt.NoModifier,QPoint(700,500));QTest.qWait(50)
assert window.activeFocusItem() is not None
root.findChild(QObject,'reviewTextInput').setProperty('text','Testo di revisione\nSeconda riga')
QMetaObject.invokeMethod(root.findChild(QObject,'reviewTextEditor'),'accept');QTest.qWait(30)
assert doc()['marks'][-1]['text']=='Testo di revisione\nSeconda riga'
window.grabWindow().save('/tmp/musescore-review-ui.png')
print('PASS: actual QML drawing, recovery, reflow, orphan/relocate, undo/redo, import rejection, tab isolation, text editor')
root.deleteLater();QTest.qWait(20)
