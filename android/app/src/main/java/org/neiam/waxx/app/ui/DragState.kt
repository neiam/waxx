package org.neiam.waxx.app.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import org.neiam.waxx.app.data.CardSummary
import org.neiam.waxx.app.data.Workflow

/**
 * Shared state for kanban drag-and-drop.
 *
 * Cells are keyed by `(stageId, subboardId?)` so the same DragState
 * serves both layouts:
 *   - 1-D (no subboards): one cell per stage, subboardId = null
 *   - 2-D (subboards):    one cell per (stage, subboard) intersection,
 *                         including a "default row" with subboardId = null
 *
 * Validity of a drop is computed from the workflow (transitions exist).
 * Same-(stage, subboard) drops are no-ops.
 */
class DragState {
    var session by mutableStateOf<Session?>(null)
        private set

    private val cellBounds = mutableStateMapOf<CellKey, Rect>()

    // Vertical center (window Y) of each rendered chip, keyed by card id.
    // Used to compute the insertion index for within-cell reorders.
    private val chipCentersY = mutableStateMapOf<String, Float>()

    fun setCellBounds(stageId: String, subboardId: String?, rect: Rect) {
        cellBounds[CellKey(stageId, subboardId)] = rect
    }

    fun clearCellBounds(stageId: String, subboardId: String?) {
        cellBounds.remove(CellKey(stageId, subboardId))
    }

    fun setChipCenterY(cardId: String, centerY: Float) {
        chipCentersY[cardId] = centerY
    }

    fun clearChipCenterY(cardId: String) {
        chipCentersY.remove(cardId)
    }

    fun start(card: CardSummary, fromStageId: String, fromSubboardId: String?, globalPos: Offset) {
        session = Session(card, fromStageId, fromSubboardId, globalPos)
    }

    fun update(delta: Offset) {
        val s = session ?: return
        session = s.copy(globalPos = s.globalPos + delta)
    }

    fun cancel() {
        session = null
    }

    /**
     * Returns the cell currently under the pointer, or null.
     */
    fun cellUnderPointer(): CellKey? {
        val s = session ?: return null
        return cellBounds.entries.firstOrNull { it.value.contains(s.globalPos) }?.key
    }

    /**
     * Drops the dragged card. Returns the target cell + computed
     * insertion index if the drop is legal, or null if it should be
     * treated as a cancel.
     *
     * - Same-cell drops are allowed and treated as reorder; the index
     *   is computed from the drop Y vs other chips' vertical centers
     *   in that cell.
     * - Cross-cell drops require a transition edge; index is null
     *   (server appends).
     */
    fun dropAt(
        workflow: Workflow?,
        cardsInCell: (CellKey) -> List<String>,
    ): Drop? {
        val s = session ?: return null
        val target = cellUnderPointer()
        val dropY = s.globalPos.y
        session = null

        target ?: return null
        if (workflow == null) return null

        val sameCell =
            target.stageId == s.fromStageId && target.subboardId == s.fromSubboardId
        return when {
            sameCell -> {
                // Insertion index = chips whose center sits above the drop,
                // excluding the dragged card itself (it's being lifted).
                val others = cardsInCell(target).filter { it != s.card.id }
                val index = others.count { (chipCentersY[it] ?: Float.MAX_VALUE) < dropY }
                Drop(target, index)
            }

            isStageTransitionValid(s.fromStageId, target.stageId, workflow) ->
                Drop(target, null)

            else -> null
        }
    }

    data class Drop(val target: CellKey, val index: Int?)

    /** Predicate used by cells for green/red highlighting during a drag. */
    fun isValidTarget(stageId: String, subboardId: String?, workflow: Workflow?): Boolean {
        val s = session ?: return false
        if (stageId == s.fromStageId && subboardId == s.fromSubboardId) return false
        if (workflow == null) return false
        return isStageTransitionValid(s.fromStageId, stageId, workflow)
    }

    private fun isStageTransitionValid(from: String, to: String, workflow: Workflow): Boolean {
        if (from == to) return true
        return workflow.transitions.any { it.from_stage_id == from && it.to_stage_id == to }
    }

    data class Session(
        val card: CardSummary,
        val fromStageId: String,
        val fromSubboardId: String?,
        val globalPos: Offset,
    )

    data class CellKey(val stageId: String, val subboardId: String?)
}
