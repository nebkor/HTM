#lang racket

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; SPATIAL POOLING
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Supporting variables and datastructures for the pseudocode
;;
;; columns: list of all columns
;;
;; input(t, j): input to this level at time t; input(t, j) is 1 if the jth input is on
;;
;; overlap(c): spatial pooler overlap of column c with a particular input pattern
;;
;; activeColumns(t): list of columns at time t that are winners due to bottom-up input
;;
;; desiredLocalActivity: parameter controlling the number of columns that are winners
;;                       after inhibition
;;
;; inhibitionRadius: average connected receptive field size of the columns
;;
;; neighbors(c): a list of all the columns within the inhibitionRadius of column c
;;
;; minOverlap: minimum number of inputs that must be active for a column to be
;;             considered during inhibition
;;
;; boost(c): boost value of column c as computed during learning; used to increase
;;           the overlap value for inactive columns
;;
;; synapse: data structure representing a synapse; contains a permanence value and
;;          the source input index
;;
;; connectedPerm: minimum permanence value for a synapse to be considered connected
;;
;; potentialSynapses(c): list of potential synapses and their permanence values in
;;                       column c
;;
;; connectedSynapses(c): subset of potentialSynapses(c) whose permanence values are
;;                       greater than connetedPerm; these are the bottom-up inputs
;;                       that are currently connected to column c.
;;
;; activeDutyCycle(c): moving average representing how often column c has been active
;;                     after inhibition (eg, over the last 1000 timesteps)
;;
;; overlapDutyCycle(c): moving average of how often column c has had > minOverlap
;;                      for its inputs
;;
;; minDutyCycle(c): variable representing the minimum desired firing rate for a column;
;;                  if a column's firing rate falls below this rate, it will be boosted;
;;                  it's set to 1% of the max firing rate of its neighbors.

;; supporting functions for the pseudocode
;;
;; kthScore(cols, k): return the kth highest overlap value in the list of columns cols
;;
;; updateActiveDutyCycle(c): computes activeDutyCycle for column c.
;;
;; updateOvelapDutyCycle(c): computes overlapDutyCycle for column c.
;;
;; averageReceptiveFieldSize(): computes the radius of the average connected receptive
;;                              field size for all columns; connected receptive field
;;                              size of a column includes only the connected synapses,
;;                              and is used to determine the extent of the lateral
;;                              inhibition between columns
;;
;; maxDutyCycle(cols): returns the max activeDutyCycle for all the columns in cols
;;
;; boostFunction(c): returns the boost value of a column; boost is a scalar >= 1.0;
;;                   if activeDutyCycle(c) > minDutyCycle(c), boost value is 1;
;;                   otherwise, boost increases linearly each timestep it's less than
;;                   minDutyCycle(c).


;; Phase 1: overlap calculation
;; Given an input vector, the first phase calculates the overlap of each column with
;; that vector.  The overlap for each column is simply the number of connected synapses
;; with active inputs, multiplied by its boost.  If this value is below minOverlap, we
;; set the overlap score to zero.
;;
;; for c in columns:
;;  overlap(c) = 0
;;
;;  for s in connectedSynapses(c)
;;   overlap(c) = overlap(c) + input(t, s.sourceInput)
;;
;;  if overlap(c) < minOverlap then
;;   overlap(c) = 0
;;  else
;;   overlap(c) = overlap(c) * boost(c)

(define (get-spatial-overlap columns connected-synapses input boost t)
  (for/list ([c columns])
    (let ([ol (get-connected-synapse-input connected-synapses input c)])
      (if (< ol *min-overlap*)
          0
          (* (hash-ref boost c) ol)))))

;; Phase 2: inhibition
;; The second phase calculates which columns remain as winners after the inhibition
;; step.  desiredLocalActivity is a parameter that controls the number of columns that
;; end up winning.  For example, if desiredLocalActivity is 10, a column will be a
;; winner if its overlap score is greater than the score of the 10'th highest column
;; within its inhibition radius
;;
;; for c in columns:
;;  minLocalActivity = kthScore(neighbors(c), desiredLocalActivity)
;;  when overlap(c) > 0 and overlap(c) ≥ minLocalActivity then
;;   activeColumns(t).append(c)

;; Phase 3: learning/permanence updating
;; The main learning rule is that permanence is incremented if the potential
;; synapse was active at this time, and decremented if it was inactive.
;;
;; Boosting occurs when a column either doesn't win often enough (as measured by
;; activeDutyCycle), or when a columns connected synapses don't overlap well with
;; any inputs often enough (as measured by overlapDutyCycle).

;; for c in activeColumns(t):
;;  for s in potentialSynapses(c):
;;   if active(s):
;;    incperm(s, pincval) // constrained to be between 0 and 1
;;   else:
;;    decperm(s, pdecval)
;;
;; for c in columns:
;;  minDutyCycle(c) = 0.01 * maxDutyCycle(neighbors(c))
;;  activeDutyCycle(c) = updateActiveDutyCycle(c)
;;  boost(c) = boostFunction(activeDutyCycle(c), minDutyCycle(c))
;;
;;  overlapdutyCycle(c) = updateOverlapDutyCycle(c)
;;  when overlapDutyCycle(c) < minDutyCycle(c):
;;   increasePermanences(c, 0.1 * connectedPerm)
;;
;; inhibitionRadius = averageReceptiveFieldSize()

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; TEMPORAL POOLING
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; supporting variables and datastructures
;;
;; cell(c,i): list of cells indexed by column, index
;;
;; cellsPerColumn: what it says on the box
;;
;; activeColumns(t): list of columns active due to bottom-up input (output from
;;                   the spatial pooler
;;
;; activeState(c,i,t): boolean vector with one element per cell; true if the cell
;;                     has current feed-forward input as well as an appropriate
;;                     temporal context
;;
;; predictiveState(c,i,t): boolean vector with one element per cell; represents
;;                         the prediction of the cell at time t, given the bottom-up
;;                         activity of other columns and the past temporal context;
;;                         if true, the cell is predicting feed-forward input in the
;;                         current temporal context.
;;
;; learnState(c,i,t): boolean vector indicating whether the cell at time t is the cell
;;                    to learn on
;;
;; activationThreshold: if the number of active connected synapses in a segment is greater
;;                      than this, the segment is said to be active
;;
;; learningRadius: area around a temporal pooler cell from which it can get lateral
;;                 connections
;;
;; initialPerm: initial permanence value for a synapse
;;
;; connectedPerm: minimum permanence value for a synapse to be considered "connected"
;;
;; minThreshold: minimum segment activity for learning
;;
;; newSynapseCount: maximum number of synapses added to a segment during learning
;;
;; segmentUpdate: datastructure holding three pieces of information required to
;;                update a given segment: a) segment index (-1 if it's a new segment),
;;                b) list of existing active synapses, and c) a flag indicating
;;                whether this segment should be marked as a sequence segment (defaults
;;                to false)
;;
;; segmentUpdateList: list of segmentUpdate structures; segmentUpdateList(c,i) is
;;                    the list of changes for cell i in column c
;;
;;
;; supporting functions used in the temporal pooling pseudocode
;;
;; segmentActive(s, t, state):
;; returns true if the number of connected synapses on segment s that are active due to
;; the given state at time t is greater than activationThreshold; the "state" can be
;; activeState or learningState
;;
;; getActiveSegment(c, i, t, state):
;; given cell(c,i), return the segment index such that segmentActive(s,t,state) is true;
;; if multiple segments are active, favor sequence segments, else favor most active
;; segments
;;
;; getBestMatchingSegment(c,i,t):
;; For the given cell(c,i) at time t, return the segment with the largest number of
;; active synapses; the permanence value of the synapses is allowed to be below
;; connectedPerm; the number of active synapses is allowed to be below connectedPerm,
;; but must be above minThreshold; returns the segment index, -1 if no segments found
;;
;; getBestMatchingCell(c, t):
;; given column c, return the cell with the best matching segment (as defined above);
;; if no cell has a matching segment, return the cell with the fewest segments
;;
;; getSegmentActiveSynapses(c, i, t, s, newSynapses = false):
;; return a segmentUpdate datastructure containing a list of proposed changes to
;; segment s; let activeSynapses be the list of active synapses where the originating
;; cells have their activeState output = 1 at time t; if newSynapses == true, add
;; newSynapseCount - length(activeSynapses) synapses are added to activeSynapses,
;; chosen randomly from the set of cells where learnState(c,i,t) == true
;;
;; adaptSegments(segmentList, positiveReinforcement):
;; this function iterates through a segmentUpdateList and reinforces each segment;
;; if positiveReinforcement == true, synapses on the active list get their permanence
;; increased by permanenceInc, and all others are decremented by permDec; if
;; positiveReinforcement == false, synapses on the active list are decremented by
;; permDec; after this step, any synapses in segmentUpdate that do not yet exist get
;; added with a permanence of initialPerm

;; Now the pseudocode!
;;
;; PHASE 1
;; Phase one calculates the activeState for each cell that is in a winning column.
;; For those columns, the code further selects one cell per column as the learning
;; cell (learnState). If the bottom-up input was predicted by any cell (ie, its
;; predictiveState output was true due to a sequence segment), then those cells
;; become active. If that segment became active from cells chose with learnState
;; true, this cell is selected as a learning cell. If the bottom-up input was not
;; predicted, then all cells in the column become active. The best matching cell
;; is chosen as the learning cell and a new segment is added to that cell.
;;
;; The following pseudocode implements combined inference with online learning.
;;
;; for c in activeColumns(t):
;;  buPredicted = false
;;  lcChosen = false
;;  for i in range(cellsPerColumn):
;;   if predictiveState(c, i, t - 1) then
;;    s = getActiveSegment(c, i, t - 1, activeState)
;;    if s.sequenceSegment:
;;     buPredicted = true
;;     activeState(c,i,t) = true
;;     if segmentActive(s, t - 1, learnState):
;;      lcChosen = true
;;      learnState(c,i,t) = true
;;
;;  if not buPredicted:
;;   for i in (range cellsPerColumn):
;;    activeState(c,i,t) = true // set all cells to be active if not predicted previously
;;
;;  if not lcChosen:
;;   l,s = getBestMatchingCell(c, t-1) // l is a cell, s is a segment? neither is used?
;;   learnState(c,i,t) = true
;;   sUpdate = getSegmentActiveSynapses(c,i,s,t-1, true)
;;   sUpdate.sequenceSegment = true
;;   segmentUpdateList.add(sUpdate)



;; PHASE 2
;; The second phase calculates the predictive state for each cell. A cell will
;; turn on its predictive state output if one of its segments becomes active, ie,
;; if enough of its lateral inputs are currently active due to feed-forward input.
;; In this case, the cell queues up the following changes: a) reinforcement of
;; the currently active segment ("activeUpdate = getSegment ..." and
;; "segmentUpdateList.add(activeUpdate)"), and b) reinforcement of a segment that
;; could have predicted this activation, ie, a segment that has a [potentially
;; weak] match to the activity during the previous time step (last two lines).
;;
;; for c, i in cells:
;;  for s in segments(c, i):
;;   if segmentActive(s, t, activeState):
;;    predictiveState(c, i, t) = true
;;
;;    activeUpdate = getSegmentActiveSynapses(i,i,s,t, false)
;;    segmentUpdateList.add(activeUpdate)
;;
;;    predSegment = getBestMatchingSegment(c,i,t - 1)
;;    predUpdate = getSegmentBestActiveSynapses(c,i,predSegment, t-1, true)
;;    segmentUpdateList.add(predUpdate)



;; PHASE 3
;; The last phase actually carries out the learning. In this phase, segment
;; updates that have been queued up are actually implemented once they get
;; feed-forward input and the cell is chosen as a learning cell (first if
;; body). Otherwise, if the cell ever stops predicting for any reason, negatively
;; reinforce the segments (second if body).
;;
;; for c,i in cells:
;;  if learnState(s,i,t):
;;   adaptSegments(segmentUpdateList(c,i), true)
;;   segmentUpdateList(c,i).delete()
;;  else if not predictiveState(c,i,t) and predictiveState(c,i,t-1):
;;   adaptSegments(segmentUpdateList(c,i), false)
;;   segmentUpdateList(c,i).delete()
