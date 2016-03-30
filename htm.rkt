#lang racket

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; SPATIAL POOLING
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Supporting variables and datastructures for the pseudocode
;;
;; columns: list of all columns

;; input(t, j): input to this level at time t; input(t, j) is 1 if the jth input is on

;; overlap(c): spatial pooler overlap of column c with a particular input pattern

;; activeColumns(t): list of columns at time t that are winners due to bottom-up input

;; desiredLocalActivity: parameter controlling the number of columns that are winners
;;                       after inhibition

;; inhibitionRadius: average connected receptive field size of the columns

;; neighbors(c): a list of all the columns within the inhibitionRadius of column c

;; minOverlap: minimum number of inputs that must be active for a column to be
;;             considered during inhibition

;; boost(c): boost value of column c as computed during learning; used to increase
;;           the overlap value for inactive columns

;; synapse: data structure representing a synapse; contains a permanence value and
;;          the source input index

;; connectedPerm: minimum permanence value for a synapse to be considered connected

;; potentialSynapses(c): list of potential synapses and their permanence values in
;;                       column c

;; connectedSynapses(c): subset of potentialSynapses(c) whose permanence values are
;;                       greater than connetedPerm; these are the bottom-up inputs
;;                       that are currently connected to column c.

;; activeDutyCycle(c): moving average representing how often column c has been active
;;                     after inhibition (eg, over the last 1000 timesteps)
;;
;; overlapDutyCycle(c): moving average of how often column c has had > minOverlap
;;                      for its inputs

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
