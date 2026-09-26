// SPDX-License-Identifier: GPL-3.0-only
// Graphical review: identities and geometry come from the live score; marks remain external.
#include "abstractnotationpaintview.h"

#include <algorithm>
#include <cmath>
#include <limits>
#include <QCryptographicHash>
#include <QDir>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QPainter>
#include <QPainterPath>
#include <QPdfWriter>
#include <QSaveFile>
#include <QStandardPaths>

#include "engraving/dom/measure.h"
#include "engraving/dom/page.h"
#include "engraving/dom/score.h"
#include "engraving/dom/segment.h"
#include "engraving/dom/staff.h"
#include "engraving/dom/system.h"
#include "notation/imasternotation.h"
#include "notation/inotationelements.h"
#include "notation/inotationinteraction.h"
#include "notation/inotationnoteinput.h"
#include "notation/inotationpainting.h"

using namespace mu::notation;
using namespace mu::engraving;

namespace {
QString measureId(const Measure* measure)
{
    return QString::fromStdString(measure->eid().toStdString());
}

QVariantMap missing(const QString& reason)
{
    return { { "valid", false }, { "reason", reason } };
}

muse::RectF staffRect(const Measure* measure, staff_idx_t staff)
{
    return measure->staffPageBoundingRect(staff).translated(measure->page()->pos());
}
}

QString AbstractNotationPaintView::reviewScoreId() const
{
    const auto elements = notationElements();
    const Score* score = elements ? elements->msScore() : nullptr;
    // Saving the score creates/persists the IDs. Never guess using measure numbers.
    if (!score || !score->eid().isValid()) {
        return {};
    }
    return QString::fromStdString(score->eid().toStdString());
}

void AbstractNotationPaintView::setReviewActive(bool active)
{
    if (active == m_reviewActive || (active && (!notation() || reviewScoreId().isEmpty()))) {
        return;
    }
    if (active) {
        const auto interaction = notationInteraction();
        interaction->noteInput()->endNoteInput(true);
        interaction->endEditText();
        interaction->endEditElement();
        interaction->clearSelection();
        m_reviewPreviousReadonly = readonly();
        setReadonly(true);
    } else {
        setReadonly(m_reviewPreviousReadonly);
    }
    if (notation()) {
        notation()->masterNotation()->notation()->setReviewInputBlocked(active);
    }
    m_reviewActive = active;
    emit reviewActiveChanged();
}

QVariantMap AbstractNotationPaintView::reviewAnchorAt(const QPointF& viewPoint) const
{
    if (!notation() || reviewScoreId().isEmpty()) {
        return missing("save-score");
    }
    const auto p = toLogical(viewPoint);
    const Page* page = notationElements()->pageByPoint(p);
    if (!page) {
        return missing("outside-page");
    }
    const Score* score = notationElements()->msScore();
    const Measure* best = nullptr;
    staff_idx_t bestStaff = 0;
    double bestDistance = std::numeric_limits<double>::max();
    for (const System* system : page->systems()) {
        for (const MeasureBase* mb : system->measures()) {
            if (!mb->isMeasure()) {
                continue;
            }
            const auto measure = toMeasure(mb);
            for (staff_idx_t i = 0; i < score->nstaves(); ++i) {
                if (!system->staff(i)->show() || !measure->visible(i)) {
                    continue;
                }
                const auto rect = staffRect(measure, i);
                if (!rect.isValid()) {
                    continue;
                }
                const double dx = p.x() - std::clamp(p.x(), rect.left(), rect.right());
                const double dy = p.y() - std::clamp(p.y(), rect.top(), rect.bottom());
                const double distance = dx * dx + dy * dy;
                if (distance < bestDistance) {
                    bestDistance = distance;
                    best = measure;
                    bestStaff = i;
                }
            }
        }
    }
    if (!best || best->isMMRest()) {
        return missing("no-visible-measure");
    }
    if (!best->eid().isValid()) {
        return missing("save-score");
    }
    const auto rect = staffRect(best, bestStaff);
    const Segment* closest = nullptr;
    double distance = std::numeric_limits<double>::max();
    for (const Segment* segment = best->first(SegmentType::ChordRest); segment; segment = segment->next(SegmentType::ChordRest)) {
        const double d = std::abs(segment->canvasPos().x() - p.x());
        if (d < distance) {
            closest = segment;
            distance = d;
        }
    }
    const double originX = closest ? closest->canvasPos().x() : rect.left();
    QVariantMap anchor {
        { "measure", measureId(best) },
        { "staff", score->staff(bestStaff)->id().toQString() },
        { "beat", closest ? closest->rtick().toString().toQString() : QString() },
        { "fraction", rect.width() > 0 ? (originX - rect.left()) / rect.width() : 0.0 }
    };
    return { { "valid", true }, { "anchor", anchor },
             { "x", originX }, { "y", rect.top() },
             { "spatium", score->staff(bestStaff)->spatium(best->tick()) } };
}

QVariantMap AbstractNotationPaintView::reviewAnchorGeometry(const QVariantMap& anchor) const
{
    if (!notation()) {
        return missing("no-score");
    }
    const Score* score = notationElements()->msScore();
    const Measure* measure = nullptr;
    // Enumerate attached measures. The EID registry can also retain deleted objects for Undo.
    for (const Measure* m = score->firstMeasure(); m; m = m->nextMeasure()) {
        if (m->eid().isValid() && measureId(m) == anchor.value("measure").toString()) {
            measure = m;
            break;
        }
    }
    if (!measure) {
        return missing("measure-deleted");
    }
    staff_idx_t staffIndex = score->nstaves();
    for (staff_idx_t i = 0; i < score->nstaves(); ++i) {
        if (score->staff(i)->id().toQString() == anchor.value("staff").toString()) {
            staffIndex = i;
            break;
        }
    }
    if (staffIndex == score->nstaves()) {
        return missing("staff-deleted");
    }
    if (!measure->system() || !measure->page() || !measure->system()->staff(staffIndex)->show()
        || !measure->visible(staffIndex)) {
        return missing("hidden");
    }
    const auto rect = staffRect(measure, staffIndex);
    double originX = rect.left() + anchor.value("fraction").toDouble() * rect.width();
    const QString beat = anchor.value("beat").toString();
    for (const Segment* segment = measure->first(SegmentType::ChordRest); segment;
         segment = segment->next(SegmentType::ChordRest)) {
        if (segment->rtick().toString().toQString() == beat) {
            originX = segment->canvasPos().x();
            break;
        }
    }
    return { { "valid", true }, { "x", originX }, { "y", rect.top() },
             { "spatium", score->staff(staffIndex)->spatium(measure->tick()) },
             { "page", static_cast<int>(measure->page()->pageNumber()) } };
}

QString AbstractNotationPaintView::reviewRecoveryPath() const
{
    if (reviewScoreId().isEmpty()) {
        return {};
    }
    const QString folder = QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation) + "/reviews";
    if (!QDir().mkpath(folder)) {
        return {};
    }
    const auto name = QCryptographicHash::hash(reviewScoreId().toUtf8(), QCryptographicHash::Sha256).toHex();
    return QUrl::fromLocalFile(folder + "/" + QString::fromLatin1(name) + ".json").toString();
}

bool AbstractNotationPaintView::exportReviewPdf(const QUrl& url, const QString& json) const
{
    if (!url.isLocalFile() || !url.toLocalFile().endsWith(".pdf", Qt::CaseInsensitive) || !notation() || json.size() > 16 * 1024 * 1024) {
        return false;
    }
    const QJsonObject document = QJsonDocument::fromJson(json.toUtf8()).object();
    if (document.value("format").toString() != "musescore-review-2"
        || document.value("scoreId").toString() != reviewScoreId()) {
        return false;
    }
    QSaveFile output(url.toLocalFile());
    if (!output.open(QIODevice::WriteOnly)) {
        return false;
    }
    const auto painting = notation()->painting();
    const auto& pages = notationElements()->pages();
    if (pages.empty()) {
        return false;
    }
    bool success = true;
    {
        QPdfWriter pdf(&output);
        pdf.setResolution(300);
        pdf.setTitle(notation()->projectWorkTitleAndPartName());
        pdf.setPageLayout(QPageLayout(QPageSize(painting->pageSizeInch().toQSizeF(), QPageSize::Inch),
                                     QPageLayout::Portrait, QMarginsF()));
        QPainter qp(&pdf);
        if (!qp.isActive()) {
            return false;
        }
        muse::draw::Painter painter(&qp, "score-review-pdf");
        for (size_t pi = 0; pi < pages.size(); ++pi) {
            if (pi && !pdf.newPage()) {
                success = false;
                break;
            }
            INotationPainting::Options opt;
            opt.fromPage = static_cast<int>(pi);
            opt.toPage = static_cast<int>(pi);
            opt.deviceDpi = pdf.logicalDpiX();
            qp.save();
            painting->paintPdf(&painter, opt);
            qp.restore();
            qp.save();
            const auto page = pages[pi];
            const auto size = page->ldata()->bbox().size();
            qp.scale(pdf.width() / size.width(), pdf.height() / size.height());
            qp.translate(-page->pos().x(), -page->pos().y());
            for (const auto value : document.value("marks").toArray()) {
                const auto mark = value.toObject();
                if (mark.value("status").toString() != "print") {
                    continue;
                }
                const auto geometry = reviewAnchorGeometry(mark.value("anchor").toObject().toVariantMap());
                if (!geometry.value("valid").toBool() || geometry.value("page").toInt() != static_cast<int>(pi)) {
                    continue;
                }
                const double sp = geometry.value("spatium").toDouble();
                const QPointF origin(geometry.value("x").toDouble(), geometry.value("y").toDouble());
                const auto points = mark.value("points").toArray();
                if (points.empty()) {
                    continue;
                }
                QPen pen(QColor("#244e80"));
                pen.setWidthF(0.22 * sp);
                pen.setCapStyle(Qt::RoundCap);
                pen.setJoinStyle(Qt::RoundJoin);
                qp.setPen(pen);
                const auto position = [origin, sp](const QJsonValue& v) {
                    const auto p = v.toObject();
                    return origin + QPointF(p.value("x").toDouble() * sp, p.value("y").toDouble() * sp);
                };
                if (mark.value("type").toString() == "text") {
                    QFont font;
                    font.setPixelSize(std::max(1, static_cast<int>(1.8 * sp)));
                    qp.setFont(font);
                    const QStringList lines = mark.value("text").toString().split('\n');
                    QPointF pos = position(points.first());
                    for (const auto& line : lines) {
                        qp.drawText(pos, line);
                        pos.ry() += 2.2 * sp;
                    }
                } else {
                    QPainterPath path(position(points.first()));
                    for (qsizetype i = 1; i < points.size(); ++i) {
                        path.lineTo(position(points[i]));
                    }
                    if (points.size() == 1) {
                        qp.drawPoint(position(points.first()));
                    } else {
                        qp.drawPath(path);
                    }
                }
            }
            qp.restore();
        }
        qp.end();
    }
    return success && output.commit();
}
