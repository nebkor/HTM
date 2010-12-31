import sys, os, re, hashlib, rand

"""In the spatial pooler, it's all first-order learning, so the column acts as
an atomic unit.  The temporal pooler, conversely, treats each cell in a column
distinctly."""

# Some globals; I think these need to go into a Region class
ACTIVE_COLUMNS = {}
PERMANENCE_INC = 0.1
PERMANENCE_DEC = 0.05 # it's harder to forget

# if a synapse's permanence is greater than this, it is connected
CONNECTED_PERM = 0.2


##-*****************************************************************************
class Synapse( object ):
    def __init__( self, inputIndex ):
        self.isactive = False
        self.inputIndex = inputIndex
        self.permanence = 0.0

    def isConnnected( self ):
        return self.permanence > CONNECTED_PERM

    def setPermanence( self, perm = 0.0 ):
        self.permanence = perm

    def getPermanence( self ):
        return self.permanence

    def isActive( self ):
        return self.isactive

    def setActive( self, active = False ):
        self.isactive = active

    def incPerm( self, inc = PERMANENCE_INC ):
        self.permanence += inc
        if self.permanence > 1.0:
            self.permanence = 1.0

    def decPerm( self, dec = PERMANENCE_DEC ):
        self.permanence -= dec
        if self.permanence < 0.0:
            self.permanence = 0.0

    def getIndex( self ):
        return self.inputIndex

##-*****************************************************************************
class Cell( object ):
    def __init__( self ):
        self.synapses = []

##-*****************************************************************************
class Column( object ):
    """Columns are made of Cells, and make Regions"""
    def __init__( self ):
        self.boost = 1.0
        self.overlap = 0.0
        self.cells = []
        self.synapses = []
        for i in range( 4 ):
            self.cells.append( Cell() )

    def setBoost( self, boost = 1.0 ):
        self.boost = boost

    def setOverlap( self, overlap = 0.0 ):
        self.overlap = overlap

    def getOverlap( self ):
        return self.overlap

    def boostOverlap( self ):
        self.overlap *= self.boost

    def getConnectedSynapses( self ):
        return map( lambda x: x.isConnected(), self.synapses )

##-*****************************************************************************
def findOverlap( columns, t, minOverlap ):
    """Spatial pooler overlap function"""
    for c in columns:
        c.setOverlap() # defaults to 0.0
        for s in c.getConnectedSynapses():
            c.setOverlap( c.getOverlap() + s.getSourcetInput( t ) )

        if c.getOverlap() < minOverlap:
            c.setOverlap()
        else:
            c.boostOverlap()


##-*****************************************************************************
def findActiveColumns( columns, t, desiredLocalActivity = 5.0 ):
    """Spatial pooler active-column-finder"""
    activeColumns = []
    for c in columns:
        if not c.getOverlap() > 0:
            continue

        minLocalActivity = kthScore( getNeighbors( c ), desiredLocalActivity )

        if c.getOverlap() >= minLocalActivity:
            activeColumns.append( c )

    ACTIVE_COLUMNS[t] = activeColumns

##-*****************************************************************************
def learnAndInhibit( activeColumns, t ):
    for c in activeColumns:
        for s in c.getSynapses():
            if s.isActive():
                s.incPerm()
            else:
                s.decPerm()
