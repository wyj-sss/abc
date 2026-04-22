#include "opt/physical/phyOpt.h"
#include "map/mio/mio.h"
#include <errno.h>
#include <math.h>
#include <stdlib.h>
#ifdef _WIN32
#include <direct.h>
#define PHY_MKDIR(path) _mkdir(path)
#else
#include <sys/stat.h>
#include <sys/types.h>
#define PHY_MKDIR(path) mkdir((path), 0777)
#endif

ABC_NAMESPACE_IMPL_START

extern Abc_Ntk_t * Abc_NtkMap( Abc_Ntk_t * pNtk, Mio_Library_t* userLib, double DelayTarget, double AreaMulti, double DelayMulti,
    float LogFan, float Slew, float Gain, int nGatesMin, int fRecovery, int fSwitching, int fSkipFanout, int fUseProfile, int fUseBuffs, int fVerbose );

typedef enum
{
    PHY_PART_HIGH = 0,
    PHY_PART_LOW  = 1,
    PHY_PART_MID  = 2
} Phy_PartType_t;

typedef struct Phy_QoR_t_
{
    double Area;
    double Delay;
} Phy_QoR_t;

#define PHY_DYN_ACC_BINS 8
#define PHY_MICRO_FEAT_DIM 11
#define PHY_SEQ_TEMPLATE_NUM 3

static float s_CritLow = 0.25f;
static float s_CritHigh = 0.90f;

/* Dynamic scheduler tuning knobs (single-point tuning). */
static int s_DynInitPct = 15;
static int s_DynLeaderPct = 5;
static int s_DynProbePct = 1;
static int s_DynPartStopTried = 10;
static int s_DynGlobalStopRounds = 2;
static int s_DynUseL2Gate = 0;
static int s_DynL2TopKInit = 2;
static int s_DynL2TopKStep = 1;

/* L0/L1/L2 funnel controls. */
static int s_DynEnableL0 = 1;
static int s_DynEnableL1 = 1;
static int s_DynL0KeepPct = 80;
static float s_DynL0WPotential = 0.55f;
static float s_DynL0WCriticality = 0.15f;
static float s_DynL0WAccPrior = 0.30f;
static float s_DynL1WindowWeight = 0.20f;
static float s_DynL1DelayPenalty = 0.70f;
static int s_DynL1WarmupSamples = 12;
static float s_DynL1InitThreshold = 0.20f;
static float s_DynL1TargetAccept = 0.45f;
static float s_DynL1AdaptLr = 0.20f;
static float s_DynL1SmoothBeta = 0.30f;
static float s_DynL1WAccPrior = 0.35f;
static float s_DynL1ThresholdMin = -1.0f;
static float s_DynL1ThresholdMax = 1.0f;
static int s_DynL1MinTryWarmupPerPart = 16;
static float s_DynAccPriorStrength = 4.0f;
static int s_DynKeepAlivePerPart = 1;
/* Low-partition relaxation knobs (default off). */
static int s_DynLowRadiusBonus = 0;
static int s_DynLowCutsBonus = 0;
static int s_DynLowNodesBonus = 0;
static int s_DynLowNodeSizeBonus = 0;
static float s_DynLowSkipSlackMin = 0.10f;
/* Low-partition funnel aggressiveness knobs (default off). */
static int s_DynLowL0KeepBoostPct = 0;
static float s_DynLowL1Relax = 0.0f;
static int s_DynLowL2TopKBonus = 0;
/* Fitted-function scorer (replaces learned micro-model inference in funnel ranking/gating). */
static int s_FitEnable = 1;
static float s_FitL0Scale = 0.35f;
static float s_FitL1Scale = 0.25f;
static float s_FitBias = -1.00f;
static float s_FitW[PHY_MICRO_FEAT_DIM] = {
    1.40f, 0.25f, 0.55f, 0.30f, -0.45f,
   -0.20f, 1.10f, 0.12f, 0.05f, 0.00f, 0.20f
};
static int s_FitLoaded = 0;
static int s_FitSampleCount = 0;
static char s_FitCoefFile[512] = {0};
/* QoR acceptance policy: default to delay non-regression + area minimization. */
static double s_QorAreaEps = 1e-3;
static double s_QorDelayAbsEps = 1e-3;
static double s_QorDelayRelTol = 0.0;
static int s_QorAcceptDelayOnly = 0;
static double s_QorGoalMinAreaImprPct = 0.0;

/* Exploration annealing: high temperature = less conservative filtering. */
static int s_DynAnnealEnable = 1;
static float s_DynAnnealStart = 1.0f;
static float s_DynAnnealMin = 0.60f;
static float s_DynAnnealDecay = 0.85f;
static int s_DynAnnealKeepBoostPct = 20;
static float s_DynAnnealL1Slack = 0.20f;

/* Partition-wise operator-sequence templates with adaptive ordering. */
static int s_SeqAdaptiveEnable = 1;
static int s_SeqWarmupPerPart = PHY_SEQ_TEMPLATE_NUM * 2;
static int s_SeqTryRun[3][PHY_SEQ_TEMPLATE_NUM] = {{0}};
static int s_SeqAccRun[3][PHY_SEQ_TEMPLATE_NUM] = {{0}};
static int s_SeqWarmCursor[3] = {0, 0, 0};

/* Global sample dedup state keyed by (node, part, window). */
static unsigned * s_MicroSampleHash = NULL;
static int s_MicroSampleHashSize = 0;
static int s_MicroSampleHashCount = 0;
static int s_MicroSampleHashSeeded = 0;
static char s_MicroSampleHashLogFile[512] = {0};

typedef struct Phy_BatchCand_t_
{
    Phy_NodeInfo_t * pSeed;
    Phy_PartType_t Part;
    int fTopPot;
    float L0Score;
    float RankScore;
    float L1Score;
    float ModelProb;
    float PriorScore;
    float Feat[PHY_MICRO_FEAT_DIM];
    int fL0Pass;
} Phy_BatchCand_t;

typedef struct Phy_MicroModel_t_
{
    int Enabled;
    int Loaded;
    int SampleCount;
    float Bias;
    float W[PHY_MICRO_FEAT_DIM];
    float BlendL0;
    float BlendL1;
    float LearnRate;
    float L2Reg;
    float ExploreFloor;
    float TrustSamples;
    int KeepTargetTryPct;
    int KeepAdaptStepPct;
    int KeepMinPct;
    int KeepMaxPct;
    char ModelFile[512];
    char LogFile[512];
} Phy_MicroModel_t;

static float Phy_NodePartPotential( const Phy_NodeInfo_t * pInfo, Phy_PartType_t Part );
static void Phy_FitInitFromEnv( void );
static float Phy_FitPredict( const float * pFeat );
static float Phy_FitBlendL0( float Heu, float Prob );
static float Phy_FitBlendL1( float Heu, float Prob );

int Phy_SetPartitionThresholds( float CritLow, float CritHigh )
{
    if ( CritLow < 0.0f || CritLow > 1.0f || CritHigh < 0.0f || CritHigh > 1.0f || CritLow >= CritHigh )
        return 0;
    s_CritLow = CritLow;
    s_CritHigh = CritHigh;
    return 1;
}

void Phy_GetPartitionThresholds( float * pCritLow, float * pCritHigh )
{
    if ( pCritLow )
        *pCritLow = s_CritLow;
    if ( pCritHigh )
        *pCritHigh = s_CritHigh;
}

static int Phy_ClampAtLeastOne( int Value, int Upper )
{
    if ( Upper <= 0 )
        return 0;
    if ( Value < 1 )
        Value = 1;
    if ( Value > Upper )
        Value = Upper;
    return Value;
}

static float Phy_ClampFloat( float Value, float MinVal, float MaxVal )
{
    if ( Value < MinVal ) return MinVal;
    if ( Value > MaxVal ) return MaxVal;
    return Value;
}

static const char * Phy_PartName( Phy_PartType_t Part )
{
    if ( Part == PHY_PART_HIGH )
        return "high";
    if ( Part == PHY_PART_LOW )
        return "low";
    return "mid";
}

static void Phy_SeqStatsResetRun( void )
{
    memset( s_SeqTryRun, 0, sizeof(s_SeqTryRun) );
    memset( s_SeqAccRun, 0, sizeof(s_SeqAccRun) );
    s_SeqWarmCursor[0] = s_SeqWarmCursor[1] = s_SeqWarmCursor[2] = 0;
}

static float Phy_SeqPosterior( int Part, int SeqId )
{
    return (float)(s_SeqAccRun[Part][SeqId] + 1) / (float)(s_SeqTryRun[Part][SeqId] + 2);
}

static float Phy_SeqBaseBias( Phy_PartType_t Part, int SeqId, const Phy_NodeInfo_t * pSeed )
{
    float Bias = 0.0f;
    if ( Part == PHY_PART_HIGH )
    {
        Bias += (SeqId == 0) ? 0.06f : (SeqId == 2 ? 0.02f : 0.0f);
        if ( pSeed && pSeed->Criticality >= 0.95f && SeqId == 0 )
            Bias += 0.02f;
    }
    else if ( Part == PHY_PART_LOW )
    {
        Bias += (SeqId == 1) ? 0.06f : (SeqId == 2 ? 0.02f : 0.0f);
        if ( pSeed && pSeed->Slack >= 0.20f && SeqId == 1 )
            Bias += 0.02f;
    }
    else
    {
        Bias += (SeqId == 2) ? 0.06f : (SeqId == 0 ? 0.02f : 0.0f);
        if ( pSeed && pSeed->Fanout > 6 && SeqId == 2 )
            Bias += 0.02f;
    }
    return Bias;
}

static int Phy_SeqSelectTemplate( Phy_PartType_t Part, const Phy_NodeInfo_t * pSeed )
{
    int p = (int)Part;
    int TotalTry = s_SeqTryRun[p][0] + s_SeqTryRun[p][1] + s_SeqTryRun[p][2];
    int SeqId;
    float BestScore = -1.0e20f;
    int BestSeq = 0;

    if ( !s_SeqAdaptiveEnable )
        return (Part == PHY_PART_HIGH) ? 0 : (Part == PHY_PART_LOW ? 1 : 2);

    if ( TotalTry < s_SeqWarmupPerPart )
    {
        int WarmSeq = s_SeqWarmCursor[p] % PHY_SEQ_TEMPLATE_NUM;
        s_SeqWarmCursor[p]++;
        return WarmSeq;
    }

    for ( SeqId = 0; SeqId < PHY_SEQ_TEMPLATE_NUM; SeqId++ )
    {
        float Posterior = Phy_SeqPosterior( p, SeqId );
        float Explore = 0.12f / (float)(1 + s_SeqTryRun[p][SeqId]);
        float Score = Posterior + Explore + Phy_SeqBaseBias( Part, SeqId, pSeed );
        if ( Score > BestScore + 1e-9f )
        {
            BestScore = Score;
            BestSeq = SeqId;
        }
    }
    return BestSeq;
}

static void Phy_SeqRecordTemplate( Phy_PartType_t Part, int SeqId, int fAccepted )
{
    int p = (int)Part;
    if ( SeqId < 0 || SeqId >= PHY_SEQ_TEMPLATE_NUM )
        return;
    s_SeqTryRun[p][SeqId]++;
    if ( fAccepted )
        s_SeqAccRun[p][SeqId]++;
}

static void Phy_StrCopySafe( char * pDst, int nDst, const char * pSrc )
{
    if ( pDst == NULL || nDst <= 0 )
        return;
    if ( pSrc == NULL )
    {
        pDst[0] = '\0';
        return;
    }
    snprintf( pDst, nDst, "%s", pSrc );
}

static void Phy_MicroSampleHashReset( void )
{
    ABC_FREE( s_MicroSampleHash );
    s_MicroSampleHash = NULL;
    s_MicroSampleHashSize = 0;
    s_MicroSampleHashCount = 0;
    s_MicroSampleHashSeeded = 0;
    s_MicroSampleHashLogFile[0] = '\0';
}

static unsigned Phy_MicroSampleHashKey( const char * pNodeName, int Part, int nWindowSize )
{
    unsigned Hash = 2166136261u;
    const unsigned char * pCur;
    char Buf[64];
    snprintf( Buf, sizeof(Buf), "%d:%d:", Part, nWindowSize );
    pCur = (const unsigned char *)Buf;
    while ( *pCur )
    {
        Hash ^= (unsigned)(*pCur++);
        Hash *= 16777619u;
    }
    pCur = (const unsigned char *)(pNodeName ? pNodeName : "");
    while ( *pCur )
    {
        Hash ^= (unsigned)(*pCur++);
        Hash *= 16777619u;
    }
    if ( Hash == 0u )
        Hash = 1u;
    return Hash;
}

static int Phy_MicroSampleHashGrow( int nNeedCount )
{
    unsigned * pOld = s_MicroSampleHash;
    int nOldSize = s_MicroSampleHashSize;
    int nNewSize = 1024;
    int i;

    while ( nNewSize < nNeedCount * 2 )
        nNewSize <<= 1;

    s_MicroSampleHash = ABC_CALLOC( unsigned, nNewSize );
    if ( s_MicroSampleHash == NULL )
    {
        s_MicroSampleHash = pOld;
        return 0;
    }

    s_MicroSampleHashSize = nNewSize;
    s_MicroSampleHashCount = 0;

    if ( pOld )
    {
        for ( i = 0; i < nOldSize; i++ )
        {
            unsigned Key = pOld[i];
            if ( Key )
            {
                int Idx = (int)(Key & (unsigned)(s_MicroSampleHashSize - 1));
                while ( s_MicroSampleHash[Idx] )
                    Idx = (Idx + 1) & (s_MicroSampleHashSize - 1);
                s_MicroSampleHash[Idx] = Key;
                s_MicroSampleHashCount++;
            }
        }
        ABC_FREE( pOld );
    }
    return 1;
}

static int Phy_MicroSampleHashContains( unsigned Key )
{
    int Idx;
    if ( Key == 0u || s_MicroSampleHash == NULL || s_MicroSampleHashSize == 0 )
        return 0;
    Idx = (int)(Key & (unsigned)(s_MicroSampleHashSize - 1));
    while ( s_MicroSampleHash[Idx] )
    {
        if ( s_MicroSampleHash[Idx] == Key )
            return 1;
        Idx = (Idx + 1) & (s_MicroSampleHashSize - 1);
    }
    return 0;
}

static int Phy_MicroSampleHashInsert( unsigned Key )
{
    int Idx;
    if ( Key == 0u )
        Key = 1u;

    if ( s_MicroSampleHashSize == 0 )
    {
        if ( !Phy_MicroSampleHashGrow( 1024 ) )
            return 0;
    }
    if ( (s_MicroSampleHashCount + 1) * 10 >= s_MicroSampleHashSize * 7 )
    {
        if ( !Phy_MicroSampleHashGrow( s_MicroSampleHashSize * 2 ) )
            return 0;
    }

    Idx = (int)(Key & (unsigned)(s_MicroSampleHashSize - 1));
    while ( s_MicroSampleHash[Idx] )
    {
        if ( s_MicroSampleHash[Idx] == Key )
            return 1;
        Idx = (Idx + 1) & (s_MicroSampleHashSize - 1);
    }
    s_MicroSampleHash[Idx] = Key;
    s_MicroSampleHashCount++;
    return 1;
}

static void Phy_MicroSampleHashSeedFromCsv( const char * pLogFile )
{
    FILE * pFile;
    char Line[2048];

    if ( pLogFile == NULL || pLogFile[0] == '\0' )
        return;

    pFile = fopen( pLogFile, "r" );
    if ( pFile == NULL )
        return;

    while ( fgets( Line, sizeof(Line), pFile ) )
    {
        int Field = 0;
        int Part = -1;
        int WindowSize = -1;
        char * pTok;
        char * pNode = NULL;
        char * pEnd;

        if ( Line[0] == '#' || strncmp( Line, "part,", 5 ) == 0 )
            continue;

        pTok = strtok( Line, "," );
        while ( pTok )
        {
            if ( Field == 0 )
                Part = atoi( pTok );
            else if ( Field == 6 )
                WindowSize = atoi( pTok );
            /* node name is the last field in both old and new layouts */
            pNode = pTok;
            Field++;
            pTok = strtok( NULL, "," );
        }
        if ( pNode == NULL || Part < 0 || Part > 2 || WindowSize <= 0 )
            continue;

        pEnd = pNode + strlen( pNode );
        while ( pEnd > pNode && (pEnd[-1] == '\n' || pEnd[-1] == '\r' || pEnd[-1] == ' ' || pEnd[-1] == '\t') )
            *--pEnd = '\0';
        if ( pNode[0] == '\0' )
            continue;

        Phy_MicroSampleHashInsert( Phy_MicroSampleHashKey( pNode, Part, WindowSize ) );
    }
    fclose( pFile );
}

static void Phy_MicroSampleHashEnsureForLog( const char * pLogFile )
{
    if ( pLogFile == NULL )
        pLogFile = "";

    if ( strcmp( s_MicroSampleHashLogFile, pLogFile ) != 0 )
    {
        Phy_MicroSampleHashReset();
        Phy_StrCopySafe( s_MicroSampleHashLogFile, (int)sizeof(s_MicroSampleHashLogFile), pLogFile );
    }

    if ( !s_MicroSampleHashSeeded )
    {
        Phy_MicroSampleHashSeedFromCsv( s_MicroSampleHashLogFile );
        s_MicroSampleHashSeeded = 1;
    }
}

static int Phy_GetEnvInt( const char * pName, int DefaultValue )
{
    char * pStr = getenv( pName );
    long Value;
    char * pEnd;
    if ( pStr == NULL || pStr[0] == '\0' )
        return DefaultValue;
    Value = strtol( pStr, &pEnd, 10 );
    if ( pEnd == pStr )
        return DefaultValue;
    return (int)Value;
}

static float Phy_GetEnvFloat( const char * pName, float DefaultValue )
{
    char * pStr = getenv( pName );
    float Value;
    char * pEnd;
    if ( pStr == NULL || pStr[0] == '\0' )
        return DefaultValue;
    Value = (float)strtod( pStr, &pEnd );
    if ( pEnd == pStr )
        return DefaultValue;
    return Value;
}

static void Phy_DynInitFromEnv( void )
{
    int fTrainWide = Phy_GetEnvInt( "PHY_DYN_TRAIN_WIDE", 0 ) ? 1 : 0;
    if ( fTrainWide )
    {
        /* Training preset: widen funnel and reduce early stopping to collect richer samples. */
        s_DynInitPct = 40;
        s_DynLeaderPct = 20;
        s_DynProbePct = 5;
        s_DynPartStopTried = 1000000;
        s_DynGlobalStopRounds = 1000000;
        s_DynUseL2Gate = 0;
        s_DynEnableL0 = 1;
        s_DynEnableL1 = 0;
        s_DynL0KeepPct = 95;
        s_DynL1WarmupSamples = 1000000;
        s_DynL1MinTryWarmupPerPart = 1000000;
        s_DynKeepAlivePerPart = 1;
    }

    s_DynInitPct = Phy_ClampAtLeastOne( Phy_GetEnvInt( "PHY_DYN_INIT_PCT", s_DynInitPct ), 100 );
    s_DynLeaderPct = Phy_ClampAtLeastOne( Phy_GetEnvInt( "PHY_DYN_LEADER_PCT", s_DynLeaderPct ), 100 );
    s_DynProbePct = Phy_ClampAtLeastOne( Phy_GetEnvInt( "PHY_DYN_PROBE_PCT", s_DynProbePct ), 100 );

    s_DynPartStopTried = Phy_GetEnvInt( "PHY_DYN_PART_STOP_TRIED", s_DynPartStopTried );
    if ( s_DynPartStopTried < 0 )
        s_DynPartStopTried = 0;
    s_DynGlobalStopRounds = Phy_GetEnvInt( "PHY_DYN_GLOBAL_STOP_ROUNDS", s_DynGlobalStopRounds );
    if ( s_DynGlobalStopRounds < 0 )
        s_DynGlobalStopRounds = 0;

    s_DynUseL2Gate = Phy_GetEnvInt( "PHY_DYN_USE_L2", s_DynUseL2Gate ) ? 1 : 0;
    s_DynL2TopKInit = Phy_ClampAtLeastOne( Phy_GetEnvInt( "PHY_DYN_L2_TOPK_INIT", s_DynL2TopKInit ), 1000 );
    s_DynL2TopKStep = Phy_ClampAtLeastOne( Phy_GetEnvInt( "PHY_DYN_L2_TOPK_STEP", s_DynL2TopKStep ), 1000 );

    s_DynEnableL0 = Phy_GetEnvInt( "PHY_DYN_ENABLE_L0", s_DynEnableL0 ) ? 1 : 0;
    s_DynEnableL1 = Phy_GetEnvInt( "PHY_DYN_ENABLE_L1", s_DynEnableL1 ) ? 1 : 0;
    s_DynL0KeepPct = Phy_ClampAtLeastOne( Phy_GetEnvInt( "PHY_DYN_L0_KEEP_PCT", s_DynL0KeepPct ), 100 );

    s_DynL1WarmupSamples = Phy_GetEnvInt( "PHY_DYN_L1_WARMUP_SAMPLES", s_DynL1WarmupSamples );
    if ( s_DynL1WarmupSamples < 0 )
        s_DynL1WarmupSamples = 0;

    s_DynL1MinTryWarmupPerPart = Phy_GetEnvInt( "PHY_DYN_L1_MIN_TRY_WARMUP_PER_PART", s_DynL1MinTryWarmupPerPart );
    if ( s_DynL1MinTryWarmupPerPart < 0 )
        s_DynL1MinTryWarmupPerPart = 0;

    s_DynL1ThresholdMin = Phy_GetEnvFloat( "PHY_DYN_L1_THRESHOLD_MIN", s_DynL1ThresholdMin );
    s_DynL1ThresholdMax = Phy_GetEnvFloat( "PHY_DYN_L1_THRESHOLD_MAX", s_DynL1ThresholdMax );
    if ( s_DynL1ThresholdMin > s_DynL1ThresholdMax )
    {
        float T = s_DynL1ThresholdMin;
        s_DynL1ThresholdMin = s_DynL1ThresholdMax;
        s_DynL1ThresholdMax = T;
    }
    s_DynL1InitThreshold = Phy_ClampFloat( Phy_GetEnvFloat( "PHY_DYN_L1_INIT_THRESHOLD", s_DynL1InitThreshold ), s_DynL1ThresholdMin, s_DynL1ThresholdMax );
    s_DynL1TargetAccept = Phy_ClampFloat( Phy_GetEnvFloat( "PHY_DYN_L1_TARGET_ACCEPT", s_DynL1TargetAccept ), 0.0f, 1.0f );
    s_DynL1AdaptLr = Phy_ClampFloat( Phy_GetEnvFloat( "PHY_DYN_L1_ADAPT_LR", s_DynL1AdaptLr ), 0.0f, 1.0f );

    s_DynLowRadiusBonus = Phy_GetEnvInt( "PHY_DYN_LOW_RADIUS_BONUS", s_DynLowRadiusBonus );
    if ( s_DynLowRadiusBonus < 0 )
        s_DynLowRadiusBonus = 0;
    if ( s_DynLowRadiusBonus > 3 )
        s_DynLowRadiusBonus = 3;

    s_DynLowCutsBonus = Phy_GetEnvInt( "PHY_DYN_LOW_CUTS_BONUS", s_DynLowCutsBonus );
    if ( s_DynLowCutsBonus < 0 )
        s_DynLowCutsBonus = 0;
    if ( s_DynLowCutsBonus > 8 )
        s_DynLowCutsBonus = 8;

    s_DynLowNodesBonus = Phy_GetEnvInt( "PHY_DYN_LOW_NODES_BONUS", s_DynLowNodesBonus );
    if ( s_DynLowNodesBonus < 0 )
        s_DynLowNodesBonus = 0;
    if ( s_DynLowNodesBonus > 3 )
        s_DynLowNodesBonus = 3;

    s_DynLowNodeSizeBonus = Phy_GetEnvInt( "PHY_DYN_LOW_NODE_SIZE_BONUS", s_DynLowNodeSizeBonus );
    if ( s_DynLowNodeSizeBonus < 0 )
        s_DynLowNodeSizeBonus = 0;
    if ( s_DynLowNodeSizeBonus > 3 )
        s_DynLowNodeSizeBonus = 3;

    s_DynLowSkipSlackMin = Phy_ClampFloat( Phy_GetEnvFloat( "PHY_DYN_LOW_SKIP_SLACK_MIN", s_DynLowSkipSlackMin ), 0.0f, 1.0f );

    s_DynLowL0KeepBoostPct = Phy_GetEnvInt( "PHY_DYN_LOW_L0_KEEP_BOOST_PCT", s_DynLowL0KeepBoostPct );
    if ( s_DynLowL0KeepBoostPct < 0 )
        s_DynLowL0KeepBoostPct = 0;
    if ( s_DynLowL0KeepBoostPct > 60 )
        s_DynLowL0KeepBoostPct = 60;

    s_DynLowL1Relax = Phy_ClampFloat( Phy_GetEnvFloat( "PHY_DYN_LOW_L1_RELAX", s_DynLowL1Relax ), 0.0f, 1.0f );

    s_DynLowL2TopKBonus = Phy_GetEnvInt( "PHY_DYN_LOW_L2_TOPK_BONUS", s_DynLowL2TopKBonus );
    if ( s_DynLowL2TopKBonus < 0 )
        s_DynLowL2TopKBonus = 0;
    if ( s_DynLowL2TopKBonus > 16 )
        s_DynLowL2TopKBonus = 16;

    s_DynKeepAlivePerPart = Phy_GetEnvInt( "PHY_DYN_KEEP_ALIVE_PER_PART", s_DynKeepAlivePerPart ) ? 1 : 0;
    s_QorAreaEps = (double)Phy_GetEnvFloat( "PHY_QOR_AREA_EPS", (float)s_QorAreaEps );
    if ( s_QorAreaEps < 0.0 )
        s_QorAreaEps = 1e-3;
    s_QorDelayAbsEps = (double)Phy_GetEnvFloat( "PHY_QOR_DELAY_EPS", (float)s_QorDelayAbsEps );
    if ( s_QorDelayAbsEps < 0.0 )
        s_QorDelayAbsEps = 1e-3;
    s_QorDelayRelTol = (double)Phy_ClampFloat( Phy_GetEnvFloat( "PHY_QOR_DELAY_REL_TOL", (float)s_QorDelayRelTol ), 0.0f, 0.10f );
    s_QorAcceptDelayOnly = Phy_GetEnvInt( "PHY_QOR_ACCEPT_DELAY_ONLY", s_QorAcceptDelayOnly ) ? 1 : 0;
    s_QorGoalMinAreaImprPct = (double)Phy_GetEnvFloat( "PHY_MICRO_GOAL_MIN_AREA_IMPR_PCT", (float)s_QorGoalMinAreaImprPct );
    if ( s_QorGoalMinAreaImprPct < 0.0 )
        s_QorGoalMinAreaImprPct = 0.0;

    s_DynAnnealEnable = Phy_GetEnvInt( "PHY_DYN_ANNEAL_ENABLE", s_DynAnnealEnable ) ? 1 : 0;
    s_DynAnnealStart = Phy_ClampFloat( Phy_GetEnvFloat( "PHY_DYN_ANNEAL_START", s_DynAnnealStart ), 0.20f, 2.00f );
    s_DynAnnealMin = Phy_ClampFloat( Phy_GetEnvFloat( "PHY_DYN_ANNEAL_MIN", s_DynAnnealMin ), 0.05f, s_DynAnnealStart );
    s_DynAnnealDecay = Phy_ClampFloat( Phy_GetEnvFloat( "PHY_DYN_ANNEAL_DECAY", s_DynAnnealDecay ), 0.50f, 0.999f );
    s_DynAnnealKeepBoostPct = Phy_GetEnvInt( "PHY_DYN_ANNEAL_KEEP_BOOST_PCT", s_DynAnnealKeepBoostPct );
    if ( s_DynAnnealKeepBoostPct < 0 )
        s_DynAnnealKeepBoostPct = 0;
    if ( s_DynAnnealKeepBoostPct > 100 )
        s_DynAnnealKeepBoostPct = 100;
    s_DynAnnealL1Slack = Phy_ClampFloat( Phy_GetEnvFloat( "PHY_DYN_ANNEAL_L1_SLACK", s_DynAnnealL1Slack ), 0.0f, 1.0f );

    s_SeqAdaptiveEnable = Phy_GetEnvInt( "PHY_SEQ_ADAPTIVE_ENABLE", s_SeqAdaptiveEnable ) ? 1 : 0;
    s_SeqWarmupPerPart = Phy_GetEnvInt( "PHY_SEQ_WARMUP_PER_PART", s_SeqWarmupPerPart );
    if ( s_SeqWarmupPerPart < PHY_SEQ_TEMPLATE_NUM )
        s_SeqWarmupPerPart = PHY_SEQ_TEMPLATE_NUM;
}

static float Phy_MicroSigmoid( float X )
{
    if ( X > 20.0f ) X = 20.0f;
    if ( X < -20.0f ) X = -20.0f;
    return 1.0f / (1.0f + expf( -X ));
}

static void Phy_MicroModelDefault( Phy_MicroModel_t * pModel )
{
    int i;
    memset( pModel, 0, sizeof(Phy_MicroModel_t) );
    pModel->Enabled = 1;
    pModel->Loaded = 0;
    pModel->SampleCount = 0;
    pModel->Bias = -1.0f;
    for ( i = 0; i < PHY_MICRO_FEAT_DIM; i++ )
        pModel->W[i] = 0.0f;
    pModel->W[0] = 1.40f;  /* potential */
    pModel->W[1] = 0.25f;  /* criticality */
    pModel->W[2] = 0.55f;  /* slack potential */
    pModel->W[3] = 0.30f;  /* structural potential */
    pModel->W[4] = -0.45f; /* fanout penalty */
    pModel->W[5] = -0.20f; /* window size penalty */
    pModel->W[6] = 1.10f;  /* acceptance prior */
    pModel->W[7] = 0.12f;  /* high part bias */
    pModel->W[8] = 0.05f;  /* low part bias */
    pModel->W[9] = 0.00f;  /* mid part bias */
    pModel->W[10] = 0.20f; /* raw slack */

    pModel->BlendL0 = 0.45f;
    pModel->BlendL1 = 0.30f;
    pModel->LearnRate = 0.05f;
    pModel->L2Reg = 0.001f;
    pModel->ExploreFloor = 0.18f;
    pModel->TrustSamples = 24.0f;
    pModel->KeepTargetTryPct = 28;
    pModel->KeepAdaptStepPct = 6;
    pModel->KeepMinPct = 35;
    pModel->KeepMaxPct = 95;
    pModel->ModelFile[0] = '\0';
    pModel->LogFile[0] = '\0';
}

static int Phy_MicroModelLoad( Phy_MicroModel_t * pModel, const char * pFileName )
{
    FILE * pFile;
    char Key[128];
    int i;
    int WeightSeen = 0;
    int BiasSeen = 0;

    if ( pFileName == NULL || pFileName[0] == '\0' )
        return 0;
    pFile = fopen( pFileName, "r" );
    if ( pFile == NULL )
        return 0;

    while ( fscanf( pFile, "%127s", Key ) == 1 )
    {
        if ( Key[0] == '#' )
        {
            char Line[1024];
            if ( fgets( Line, sizeof(Line), pFile ) == NULL )
                break;
            continue;
        }
        if ( strcmp( Key, "bias" ) == 0 )
        {
            if ( fscanf( pFile, "%f", &pModel->Bias ) == 1 )
                BiasSeen = 1;
            continue;
        }
        if ( strcmp( Key, "sample_count" ) == 0 )
        {
            int Count = 0;
            if ( fscanf( pFile, "%d", &Count ) == 1 )
                pModel->SampleCount = Count;
            continue;
        }
        if ( strcmp( Key, "weights" ) == 0 )
        {
            int Ok = 1;
            for ( i = 0; i < PHY_MICRO_FEAT_DIM; i++ )
                if ( fscanf( pFile, "%f", &pModel->W[i] ) != 1 )
                    Ok = 0;
            WeightSeen = Ok;
            continue;
        }
    }
    fclose( pFile );
    pModel->Loaded = BiasSeen && WeightSeen;
    return pModel->Loaded;
}

static int Phy_MicroModelSave( const Phy_MicroModel_t * pModel )
{
    FILE * pFile;
    int i;
    if ( pModel->ModelFile[0] == '\0' )
        return 0;
    pFile = fopen( pModel->ModelFile, "w" );
    if ( pFile == NULL )
        return 0;
    fprintf( pFile, "# phy micro model v1\n" );
    fprintf( pFile, "bias %.8f\n", pModel->Bias );
    fprintf( pFile, "sample_count %d\n", pModel->SampleCount );
    fprintf( pFile, "weights" );
    for ( i = 0; i < PHY_MICRO_FEAT_DIM; i++ )
        fprintf( pFile, " %.8f", pModel->W[i] );
    fprintf( pFile, "\n" );
    fclose( pFile );
    return 1;
}

static void Phy_MicroModelInitFromEnv( Phy_MicroModel_t * pModel )
{
    char * pModelFile;
    char * pLogFile;
    Phy_MicroSampleHashReset();
    Phy_MicroModelDefault( pModel );

    pModel->Enabled = Phy_GetEnvInt( "PHY_MICRO_ENABLE", pModel->Enabled ) ? 1 : 0;
    pModel->BlendL0 = Phy_ClampFloat( Phy_GetEnvFloat( "PHY_MICRO_BLEND_L0", pModel->BlendL0 ), 0.0f, 1.0f );
    pModel->BlendL1 = Phy_ClampFloat( Phy_GetEnvFloat( "PHY_MICRO_BLEND_L1", pModel->BlendL1 ), 0.0f, 1.0f );
    pModel->LearnRate = Phy_ClampFloat( Phy_GetEnvFloat( "PHY_MICRO_LR", pModel->LearnRate ), 0.0001f, 1.0f );
    pModel->L2Reg = Phy_ClampFloat( Phy_GetEnvFloat( "PHY_MICRO_L2", pModel->L2Reg ), 0.0f, 1.0f );
    pModel->ExploreFloor = Phy_ClampFloat( Phy_GetEnvFloat( "PHY_MICRO_EXPLORE_FLOOR", pModel->ExploreFloor ), 0.0f, 1.0f );
    pModel->TrustSamples = Phy_ClampFloat( Phy_GetEnvFloat( "PHY_MICRO_TRUST_SAMPLES", pModel->TrustSamples ), 1.0f, 1000000.0f );
    pModel->KeepTargetTryPct = Phy_ClampAtLeastOne( Phy_GetEnvInt( "PHY_MICRO_TRY_TARGET_PCT", pModel->KeepTargetTryPct ), 99 );
    pModel->KeepAdaptStepPct = Phy_ClampAtLeastOne( Phy_GetEnvInt( "PHY_MICRO_KEEP_STEP_PCT", pModel->KeepAdaptStepPct ), 50 );
    pModel->KeepMinPct = Phy_ClampAtLeastOne( Phy_GetEnvInt( "PHY_MICRO_KEEP_MIN_PCT", pModel->KeepMinPct ), 99 );
    pModel->KeepMaxPct = Phy_ClampAtLeastOne( Phy_GetEnvInt( "PHY_MICRO_KEEP_MAX_PCT", pModel->KeepMaxPct ), 99 );
    if ( pModel->KeepMinPct > pModel->KeepMaxPct )
    {
        int T = pModel->KeepMinPct;
        pModel->KeepMinPct = pModel->KeepMaxPct;
        pModel->KeepMaxPct = T;
    }

    pModelFile = getenv( "PHY_MICRO_MODEL_FILE" );
    pLogFile = getenv( "PHY_MICRO_TRAIN_CSV" );
    Phy_StrCopySafe( pModel->ModelFile, sizeof(pModel->ModelFile), pModelFile );
    Phy_StrCopySafe( pModel->LogFile, sizeof(pModel->LogFile), pLogFile );

    if ( pModel->Enabled && pModel->ModelFile[0] )
        Phy_MicroModelLoad( pModel, pModel->ModelFile );
}

static int Phy_FitLoadFromFile( const char * pFileName )
{
    FILE * pFile;
    char Key[128];
    int i;
    int WeightSeen = 0;
    int BiasSeen = 0;

    if ( pFileName == NULL || pFileName[0] == '\0' )
        return 0;
    pFile = fopen( pFileName, "r" );
    if ( pFile == NULL )
        return 0;

    while ( fscanf( pFile, "%127s", Key ) == 1 )
    {
        if ( Key[0] == '#' )
        {
            char Line[1024];
            if ( fgets( Line, sizeof(Line), pFile ) == NULL )
                break;
            continue;
        }
        if ( strcmp( Key, "bias" ) == 0 )
        {
            if ( fscanf( pFile, "%f", &s_FitBias ) == 1 )
                BiasSeen = 1;
            continue;
        }
        if ( strcmp( Key, "sample_count" ) == 0 )
        {
            int Count = 0;
            if ( fscanf( pFile, "%d", &Count ) == 1 )
                s_FitSampleCount = Count;
            continue;
        }
        if ( strcmp( Key, "weights" ) == 0 )
        {
            int Ok = 1;
            for ( i = 0; i < PHY_MICRO_FEAT_DIM; i++ )
                if ( fscanf( pFile, "%f", &s_FitW[i] ) != 1 )
                    Ok = 0;
            WeightSeen = Ok;
            continue;
        }
    }
    fclose( pFile );
    s_FitLoaded = BiasSeen && WeightSeen;
    return s_FitLoaded;
}

static void Phy_FitInitFromEnv( void )
{
    char * pCoefFile;
    s_FitEnable = Phy_GetEnvInt( "PHY_FIT_ENABLE", s_FitEnable ) ? 1 : 0;
    s_FitL0Scale = Phy_ClampFloat( Phy_GetEnvFloat( "PHY_FIT_L0_SCALE", s_FitL0Scale ), 0.0f, 2.0f );
    s_FitL1Scale = Phy_ClampFloat( Phy_GetEnvFloat( "PHY_FIT_L1_SCALE", s_FitL1Scale ), 0.0f, 2.0f );

    pCoefFile = getenv( "PHY_FIT_COEF_FILE" );
    Phy_StrCopySafe( s_FitCoefFile, sizeof(s_FitCoefFile), pCoefFile );
    s_FitLoaded = 0;
    s_FitSampleCount = 0;
    if ( s_FitEnable && s_FitCoefFile[0] )
        Phy_FitLoadFromFile( s_FitCoefFile );
}

static float Phy_FitPredict( const float * pFeat )
{
    float Dot = s_FitBias;
    int i;
    if ( !s_FitEnable )
        return 0.5f;
    for ( i = 0; i < PHY_MICRO_FEAT_DIM; i++ )
        Dot += s_FitW[i] * pFeat[i];
    return Phy_MicroSigmoid( Dot );
}

static float Phy_FitBlendL0( float Heu, float Prob )
{
    return Heu + s_FitL0Scale * (Prob - 0.5f);
}

static float Phy_FitBlendL1( float Heu, float Prob )
{
    return Heu + s_FitL1Scale * (2.0f * Prob - 1.0f);
}

static void Phy_MicroBuildFeatures(
    const Phy_NodeInfo_t * pSeed,
    Phy_PartType_t Part,
    int nWindowSize,
    float Prior,
    float * pFeat )
{
    float FanNorm = Phy_ClampFloat( (float)pSeed->Fanout / 12.0f, 0.0f, 1.0f );
    float WinNorm = Phy_ClampFloat( (float)nWindowSize / 32.0f, 0.0f, 1.0f );
    float SlackNorm = Phy_ClampFloat( pSeed->Slack / 0.30f, 0.0f, 1.0f );
    pFeat[0] = Phy_NodePartPotential( pSeed, Part );
    pFeat[1] = pSeed->Criticality;
    pFeat[2] = pSeed->SlackPotential;
    pFeat[3] = pSeed->StructPotential;
    pFeat[4] = FanNorm;
    pFeat[5] = WinNorm;
    pFeat[6] = Prior;
    pFeat[7] = (Part == PHY_PART_HIGH) ? 1.0f : 0.0f;
    pFeat[8] = (Part == PHY_PART_LOW) ? 1.0f : 0.0f;
    pFeat[9] = (Part == PHY_PART_MID) ? 1.0f : 0.0f;
    pFeat[10] = SlackNorm;
}

static float Phy_MicroPredictRaw( const Phy_MicroModel_t * pModel, const float * pFeat )
{
    float Dot = pModel->Bias;
    int i;
    for ( i = 0; i < PHY_MICRO_FEAT_DIM; i++ )
        Dot += pModel->W[i] * pFeat[i];
    return Phy_MicroSigmoid( Dot );
}

static float Phy_MicroPredict( const Phy_MicroModel_t * pModel, const float * pFeat )
{
    float Prob;
    float Trust;
    float Conf;
    if ( !pModel->Enabled )
        return 0.5f;
    Prob = Phy_MicroPredictRaw( pModel, pFeat );
    Trust = pModel->TrustSamples;
    if ( Trust <= 1.0f )
        return Prob;
    Conf = Phy_ClampFloat( (float)pModel->SampleCount / Trust, 0.0f, 1.0f );
    return (1.0f - Conf) * 0.5f + Conf * Prob;
}

static float Phy_MicroBlendL0( const Phy_MicroModel_t * pModel, float Heu, float Prob )
{
    float Blend = pModel->Enabled ? pModel->BlendL0 : 0.0f;
    return (1.0f - Blend) * Heu + Blend * Prob;
}

static float Phy_MicroBlendL1( const Phy_MicroModel_t * pModel, float Heu, float Prob )
{
    float Blend = pModel->Enabled ? pModel->BlendL1 : 0.0f;
    float ProbSigned = 2.0f * Prob - 1.0f;
    return (1.0f - Blend) * Heu + Blend * ProbSigned;
}

static void Phy_MicroOnlineUpdate( Phy_MicroModel_t * pModel, const float * pFeat, int Label )
{
    float Pred;
    float Err;
    int i;
    if ( !pModel->Enabled )
        return;
    Pred = Phy_MicroPredictRaw( pModel, pFeat );
    Err = (Label ? 1.0f : 0.0f) - Pred;
    for ( i = 0; i < PHY_MICRO_FEAT_DIM; i++ )
    {
        float Grad = Err * pFeat[i] - pModel->L2Reg * pModel->W[i];
        pModel->W[i] += pModel->LearnRate * Grad;
        pModel->W[i] = Phy_ClampFloat( pModel->W[i], -8.0f, 8.0f );
    }
    pModel->Bias += pModel->LearnRate * Err;
    pModel->Bias = Phy_ClampFloat( pModel->Bias, -8.0f, 8.0f );
    pModel->SampleCount++;
}

static void Phy_MicroLogSample(
    const Phy_MicroModel_t * pModel,
    Phy_PartType_t Part,
    const Phy_NodeInfo_t * pSeed,
    int nWindowSize,
    float Prior,
    float ModelProb,
    int Accepted,
    int GoalHit,
    double AreaImpr,
    double DelayDelta )
{
    FILE * pFile;
    long Size = 0;
    unsigned SampleKey;
    if ( pModel->LogFile[0] == '\0' || pSeed == NULL )
        return;

    Phy_MicroSampleHashEnsureForLog( pModel->LogFile );
    SampleKey = Phy_MicroSampleHashKey( pSeed->NodeName, (int)Part, nWindowSize );
    if ( Phy_MicroSampleHashContains( SampleKey ) )
        return;

    pFile = fopen( pModel->LogFile, "a+" );
    if ( pFile == NULL )
        return;
    fseek( pFile, 0, SEEK_END );
    Size = ftell( pFile );
    if ( Size == 0 )
    {
        fprintf( pFile, "part,pot,criticality,slack_potential,struct_potential,fanout,window_size,prior,model_prob,accepted,goal_hit,area_impr_pct,delay_delta,node\n" );
    }
    fprintf( pFile, "%d,%.6f,%.6f,%.6f,%.6f,%d,%d,%.6f,%.6f,%d,%d,%.6f,%.6f,%s\n",
        (int)Part,
        Phy_NodePartPotential( pSeed, Part ),
        pSeed->Criticality,
        pSeed->SlackPotential,
        pSeed->StructPotential,
        pSeed->Fanout,
        nWindowSize,
        Prior,
        ModelProb,
        Accepted ? 1 : 0,
        GoalHit ? 1 : 0,
        AreaImpr,
        DelayDelta,
        pSeed->NodeName );
    fclose( pFile );
    Phy_MicroSampleHashInsert( SampleKey );
}

static int Phy_BatchCandCmpByL0Desc( const void * pA, const void * pB )
{
    const Phy_BatchCand_t * pC1 = *(const Phy_BatchCand_t * const *)pA;
    const Phy_BatchCand_t * pC2 = *(const Phy_BatchCand_t * const *)pB;
    if ( pC1->RankScore < pC2->RankScore )
        return 1;
    if ( pC1->RankScore > pC2->RankScore )
        return -1;
    if ( pC1->L0Score < pC2->L0Score )
        return 1;
    if ( pC1->L0Score > pC2->L0Score )
        return -1;
    return (pC1->pSeed->ObjId > pC2->pSeed->ObjId) - (pC1->pSeed->ObjId < pC2->pSeed->ObjId);
}

static int Phy_ParseNodeIdFromName( const char * pName )
{
    int Id = 0;
    int i = 0;
    if ( pName == NULL || pName[0] != 'n' )
        return -1;
    i = 1;
    if ( pName[i] < '0' || pName[i] > '9' )
        return -1;
    while ( pName[i] >= '0' && pName[i] <= '9' )
    {
        Id = Id * 10 + (pName[i] - '0');
        i++;
    }
    return Id;
}

static int Phy_GetWindowCenterObjId( Abc_Ntk_t * pNtk, const Phy_NodeInfo_t * pSeed )
{
    Abc_Obj_t * pObj;
    int Id;
    if ( pNtk == NULL || pSeed == NULL )
        return -1;

    pObj = Abc_NtkFindNode( pNtk, (char *)pSeed->NodeName );
    if ( pObj && Abc_ObjIsNode(pObj) )
        return pObj->Id;

    Id = pSeed->ObjId;
    if ( Id > 0 && Id < Abc_NtkObjNumMax(pNtk) )
    {
        pObj = Abc_NtkObj( pNtk, Id );
        if ( pObj && Abc_ObjIsNode(pObj) )
            return Id;
    }

    Id = Phy_ParseNodeIdFromName( pSeed->NodeName );
    if ( Id > 0 && Id < Abc_NtkObjNumMax(pNtk) )
    {
        pObj = Abc_NtkObj( pNtk, Id );
        if ( pObj && Abc_ObjIsNode(pObj) )
            return Id;
    }
    return -1;
}

static int Phy_WindowRadius( const Phy_NodeInfo_t * pSeed, Phy_PartType_t Part, int nWindowSize )
{
    int Radius = (nWindowSize >= 32) ? 5 : (nWindowSize >= 16 ? 4 : (nWindowSize >= 8 ? 3 : 2));
    if ( Part == PHY_PART_HIGH )
        Radius += 1;
    if ( Part == PHY_PART_LOW )
        Radius -= 1;
    if ( Part == PHY_PART_LOW )
        Radius += s_DynLowRadiusBonus;
    if ( pSeed && pSeed->Slack < 0.05f )
        Radius += 1;
    if ( pSeed && pSeed->Fanout > 6 )
        Radius -= 1;
    if ( Radius < 2 ) Radius = 2;
    if ( Radius > 6 ) Radius = 6;
    return Radius;
}

static int Phy_MkDirIfNeeded( const char * pDir )
{
    if ( pDir == NULL || pDir[0] == '\0' )
        return 0;
    if ( PHY_MKDIR( pDir ) == 0 )
        return 1;
    return errno == EEXIST;
}

static int Phy_EnsureTmpDir( void )
{
    if ( !Phy_MkDirIfNeeded( "my_work" ) )
        return 0;
    if ( !Phy_MkDirIfNeeded( "my_work/tmp" ) )
        return 0;
    return 1;
}

static int Phy_EvalMappedQoR( Abc_Ntk_t * pNtk, Phy_QoR_t * pQoR )
{
    Abc_Ntk_t * pNtkDup, * pMapped;
    double DelayTarget = -1;
    double AreaMulti = 0.0;
    double DelayMulti = 0.0;
    float LogFan = 0.0f;
    float Slew = 0.0f;
    float Gain = 250.0f;
    int nGatesMin = 0;
    int fRecovery = 1;
    int fSwitching = 0;
    int fSkipFanout = 0;
    int fUseProfile = 0;
    int fUseBuffs = 0;
    int fVerbose = 0;

    if ( pNtk == NULL || pQoR == NULL )
        return 0;

    pNtkDup = Abc_NtkDup( pNtk );
    if ( pNtkDup == NULL )
        return 0;

    pMapped = Abc_NtkMap( pNtkDup, NULL, DelayTarget, AreaMulti, DelayMulti, LogFan, Slew, Gain,
        nGatesMin, fRecovery, fSwitching, fSkipFanout, fUseProfile, fUseBuffs, fVerbose );
    Abc_NtkDelete( pNtkDup );
    if ( pMapped == NULL )
        return 0;

    pQoR->Area = Abc_NtkGetMappedArea( pMapped );
    pQoR->Delay = (double)Abc_NtkDelayTrace( pMapped, NULL, NULL, 0 );
    Abc_NtkDelete( pMapped );
    return 1;
}

static double Phy_QorDelayBudget( Phy_QoR_t Before )
{
    double Rel = Before.Delay * s_QorDelayRelTol;
    if ( Rel < 0.0 )
        Rel = 0.0;
    return s_QorDelayAbsEps + Rel;
}

static int Phy_QorDelayNoWorse( Phy_QoR_t Before, Phy_QoR_t After )
{
    return After.Delay <= Before.Delay + Phy_QorDelayBudget( Before );
}

static int Phy_QorGoalHit( Phy_QoR_t Before, Phy_QoR_t After )
{
    double AreaImprPct;
    if ( !Phy_QorDelayNoWorse( Before, After ) || Before.Area <= 0.0 )
        return 0;
    if ( After.Area > Before.Area - s_QorAreaEps )
        return 0;
    AreaImprPct = (Before.Area - After.Area) * 100.0 / Before.Area;
    return AreaImprPct >= s_QorGoalMinAreaImprPct;
}

static int Phy_AcceptByMappedQoR( Phy_PartType_t Part, Phy_QoR_t Before, Phy_QoR_t After )
{
    (void)Part;
    if ( !Phy_QorDelayNoWorse( Before, After ) )
        return 0;
    if ( After.Area < Before.Area - s_QorAreaEps )
        return 1;
    if ( s_QorAcceptDelayOnly && After.Delay < Before.Delay - s_QorDelayAbsEps && After.Area <= Before.Area + s_QorAreaEps )
        return 1;
    return 0;
}

static int Phy_ClassifyMappedReject( Phy_PartType_t Part, Phy_QoR_t Before, Phy_QoR_t After )
{
    int fDelayWorse;
    int fAreaWorse;
    (void)Part;

    fDelayWorse = !Phy_QorDelayNoWorse( Before, After );
    fAreaWorse = After.Area > Before.Area + s_QorAreaEps;

    if ( fDelayWorse && fAreaWorse )
        return 4; /* both worse */
    if ( fDelayWorse )
        return 5; /* delay guard violation */
    if ( fAreaWorse )
        return 3; /* area worse */
    return 1; /* tradeoff / policy reject */
}

static int Phy_MarkedNameHas( Vec_Ptr_t * vMarkedNames, const char * pName )
{
    char * pEntry;
    int i;
    if ( pName == NULL || pName[0] == '\0' )
        return 0;
    Vec_PtrForEachEntry( char *, vMarkedNames, pEntry, i )
        if ( strcmp( pEntry, pName ) == 0 )
            return 1;
    return 0;
}

static void Phy_MarkedNameAdd( Vec_Ptr_t * vMarkedNames, const char * pName )
{
    char * pDup;
    int nLen;
    if ( pName == NULL || pName[0] == '\0' || Phy_MarkedNameHas( vMarkedNames, pName ) )
        return;
    nLen = (int)strlen( pName );
    pDup = ABC_ALLOC( char, nLen + 1 );
    memcpy( pDup, pName, nLen + 1 );
    Vec_PtrPush( vMarkedNames, pDup );
}

static void Phy_MarkedNameFree( Vec_Ptr_t * vMarkedNames )
{
    char * pEntry;
    int i;
    if ( vMarkedNames == NULL )
        return;
    Vec_PtrForEachEntry( char *, vMarkedNames, pEntry, i )
        ABC_FREE( pEntry );
    Vec_PtrFree( vMarkedNames );
}

static void Phy_MarkAffectedAccepted( unsigned char * pMarked, int nMaxObjId, Vec_Ptr_t * vMarkedNames, const Phy_NodeInfo_t * pSeed, Phy_Data_t * pRoundData )
{
    Phy_NodeInfo_t * pInfo;
    int i;
    if ( pSeed == NULL || pRoundData == NULL )
        return;

    if ( pSeed->ObjId >= 0 && pSeed->ObjId <= nMaxObjId )
        pMarked[pSeed->ObjId] = 1;
    Phy_MarkedNameAdd( vMarkedNames, pSeed->NodeName );

    if ( pSeed->Fanin0ObjId >= 0 && pSeed->Fanin0ObjId <= nMaxObjId )
        pMarked[pSeed->Fanin0ObjId] = 1;
    if ( pSeed->Fanin1ObjId >= 0 && pSeed->Fanin1ObjId <= nMaxObjId )
        pMarked[pSeed->Fanin1ObjId] = 1;
    Phy_MarkedNameAdd( vMarkedNames, pSeed->Fanin0 );
    Phy_MarkedNameAdd( vMarkedNames, pSeed->Fanin1 );

    Vec_PtrForEachEntry( Phy_NodeInfo_t *, pRoundData->vNodes, pInfo, i )
    {
        if ( pInfo->Fanin0ObjId == pSeed->ObjId || pInfo->Fanin1ObjId == pSeed->ObjId )
        {
            if ( pInfo->ObjId >= 0 && pInfo->ObjId <= nMaxObjId )
                pMarked[pInfo->ObjId] = 1;
            Phy_MarkedNameAdd( vMarkedNames, pInfo->NodeName );
        }
    }
}

static Phy_Data_t * Phy_RefreshDataForRound( Abc_Frame_t * pAbc, const Phy_Data_t * pDataBase, int fVerbose )
{
    char Cmd[1200];
    const char * pOut = (pDataBase && pDataBase->FileName[0]) ? pDataBase->FileName : "phyopt_refresh.csv";
    Phy_Data_t * pDataNew;

    if ( Cmd_CommandExecute( pAbc, "map_oto" ) )
        return NULL;
    snprintf( Cmd, sizeof(Cmd), "mapper_extract -o %s", pOut );
    if ( Cmd_CommandExecute( pAbc, Cmd ) )
        return NULL;
    if ( Cmd_CommandExecute( pAbc, "strash" ) )
        return NULL;

    pDataNew = Phy_DataReadCsv( pOut,
        pDataBase ? pDataBase->AlphaLow : 0.3f,
        pDataBase ? pDataBase->AlphaMiddle : 0.5f,
        pDataBase ? pDataBase->AlphaHigh : 0.8f,
        fVerbose );
    return pDataNew;
}

static float Phy_NodePartPotential( const Phy_NodeInfo_t * pInfo, Phy_PartType_t Part )
{
    if ( Part == PHY_PART_HIGH )
        return pInfo->OptPotentialHigh;
    if ( Part == PHY_PART_LOW )
        return pInfo->OptPotentialLow;
    return pInfo->OptPotentialMiddle;
}

static int Phy_NodePart( const Phy_NodeInfo_t * pInfo )
{
    if ( pInfo->Criticality >= s_CritHigh )
        return PHY_PART_HIGH;
    if ( pInfo->Criticality <= s_CritLow )
        return PHY_PART_LOW;
    return PHY_PART_MID;
}

static Phy_PartType_t s_SortPart = PHY_PART_HIGH;

static int Phy_NodeCmpByPartPotential( const void * pA, const void * pB )
{
    const Phy_NodeInfo_t * pN1 = *(const Phy_NodeInfo_t * const *)pA;
    const Phy_NodeInfo_t * pN2 = *(const Phy_NodeInfo_t * const *)pB;
    float P1 = Phy_NodePartPotential( pN1, s_SortPart );
    float P2 = Phy_NodePartPotential( pN2, s_SortPart );
    if ( P1 < P2 )
        return 1;
    if ( P1 > P2 )
        return -1;
    return (pN1->ObjId > pN2->ObjId) - (pN1->ObjId < pN2->ObjId);
}

static int Phy_RunSeqTemplateOps( Abc_Frame_t * pAbc, Phy_PartType_t Part, int SeqTemplate )
{
    const char * pCmds[5] = { NULL };
    int nCmds = 0;
    int i;

    SeqTemplate %= PHY_SEQ_TEMPLATE_NUM;

    if ( Part == PHY_PART_HIGH )
    {
        if ( SeqTemplate == 0 )
        {
            pCmds[nCmds++] = "balance";
            pCmds[nCmds++] = "rewrite -z";
            pCmds[nCmds++] = "balance";
        }
        else if ( SeqTemplate == 1 )
        {
            pCmds[nCmds++] = "rewrite -z";
            pCmds[nCmds++] = "balance";
            pCmds[nCmds++] = "rewrite -z";
        }
        else
        {
            pCmds[nCmds++] = "balance";
            pCmds[nCmds++] = "refactor -z";
            pCmds[nCmds++] = "rewrite -z";
        }
    }
    else if ( Part == PHY_PART_LOW )
    {
        if ( SeqTemplate == 0 )
        {
            pCmds[nCmds++] = "rewrite -z";
            pCmds[nCmds++] = "balance";
            pCmds[nCmds++] = "refactor -z";
        }
        else if ( SeqTemplate == 1 )
        {
            pCmds[nCmds++] = "refactor -z";
            pCmds[nCmds++] = "rewrite -z";
            pCmds[nCmds++] = "balance";
            pCmds[nCmds++] = "rewrite -z";
        }
        else
        {
            pCmds[nCmds++] = "rewrite -z";
            pCmds[nCmds++] = "refactor -z";
            pCmds[nCmds++] = "balance";
        }
    }
    else
    {
        if ( SeqTemplate == 0 )
        {
            pCmds[nCmds++] = "balance";
            pCmds[nCmds++] = "rewrite -z";
            pCmds[nCmds++] = "refactor -z";
        }
        else if ( SeqTemplate == 1 )
        {
            pCmds[nCmds++] = "rewrite -z";
            pCmds[nCmds++] = "refactor -z";
            pCmds[nCmds++] = "rewrite -z";
            pCmds[nCmds++] = "balance";
        }
        else
        {
            pCmds[nCmds++] = "refactor -z";
            pCmds[nCmds++] = "balance";
            pCmds[nCmds++] = "rewrite -z";
        }
    }

    for ( i = 0; i < nCmds; i++ )
        if ( Cmd_CommandExecute( pAbc, pCmds[i] ) )
            return 1;
    return 0;
}

static int Phy_OptWindowPass( Abc_Frame_t * pAbc, const Phy_NodeInfo_t * pSeed, Phy_PartType_t Part, int nWindowSize, int nObjIdCenter, int nRadius, int SeqTemplate )
{
    Abc_Ntk_t * pNtk = Abc_FrameReadNtk( pAbc );
    Abc_Ntk_t * pNtkBase;
    Abc_Ntk_t * pNtkBeforeExt;
    Abc_Ntk_t * pNtkBeforeIns;
    Abc_Obj_t * pCenter;
    int RetValue;
    int nCutsMax, nNodesMax, nLevelsOdc, nNodeSizeMax, nConeSizeMax;
    char Cmd[1024];
    char WinFile[512];
    int fWinFileWritten = 0;
    int fUseZerosRwr = 1, fUseZerosRef = 1, fPlaceEnable = 0;
    int fUpdateLevel = 1, fVerbose = 0, fVeryVerbose = 0, fUseDcs = 0;

    extern int Abc_NtkOrchLocal( Abc_Ntk_t * pNtk, int fUseZeros_rwr, int fUseZeros_ref,
        int fPlaceEnable, int nCutsMax, int nNodesMax, int nLevelsOdc, int fUpdateLevel,
        int fVerbose, int fVeryVerbose, int nNodeSizeMax, int nConeSizeMax, int fUseDcs );

    if ( pNtk == NULL || nObjIdCenter <= 0 || nRadius <= 0 )
        return 1;

    pCenter = (nObjIdCenter < Abc_NtkObjNumMax(pNtk)) ? Abc_NtkObj( pNtk, nObjIdCenter ) : NULL;
    if ( pCenter == NULL || !Abc_ObjIsNode(pCenter) )
        return 1;

    pNtkBase = Abc_NtkDup( pNtk );
    if ( pNtkBase == NULL )
        return 1;

    pNtkBeforeExt = Abc_FrameReadNtk( pAbc );
    snprintf( Cmd, sizeof(Cmd), "extwin -N %d -D %d", nObjIdCenter, nRadius );
    if ( Cmd_CommandExecute( pAbc, Cmd ) )
    {
        Abc_FrameReplaceCurrentNetwork( pAbc, pNtkBase );
        return 1;
    }

    pNtk = Abc_FrameReadNtk( pAbc );
    if ( pNtk == pNtkBeforeExt )
    {
        Abc_FrameReplaceCurrentNetwork( pAbc, pNtkBase );
        return 1;
    }

    if ( Cmd_CommandExecute( pAbc, "strash" ) )
    {
        Abc_FrameReplaceCurrentNetwork( pAbc, pNtkBase );
        return 1;
    }

    pNtk = Abc_FrameReadNtk( pAbc );
    if ( pNtk == NULL || !Abc_NtkIsStrash(pNtk) )
    {
        Abc_FrameReplaceCurrentNetwork( pAbc, pNtkBase );
        return 1;
    }

    if ( Part == PHY_PART_HIGH )
    {
        nCutsMax = (nWindowSize > 16) ? 12 : 10;
        nNodesMax = 2;
        nLevelsOdc = 0;
    }
    else if ( Part == PHY_PART_LOW )
    {
        nCutsMax = 8;
        nNodesMax = 1;
        nLevelsOdc = 1;
        nCutsMax += s_DynLowCutsBonus;
        nNodesMax += s_DynLowNodesBonus;
    }
    else
    {
        nCutsMax = (nWindowSize > 16) ? 10 : 9;
        nNodesMax = 1;
        nLevelsOdc = 0;
    }

    nNodeSizeMax = nWindowSize >= 24 ? 12 : (nWindowSize >= 8 ? 10 : 8);
    if ( pSeed && pSeed->Criticality >= s_CritHigh )
        nNodeSizeMax += 1;
    if ( pSeed && pSeed->Fanout > 4 )
        nNodeSizeMax -= 1;
    if ( Part == PHY_PART_LOW )
        nNodeSizeMax -= 1;
    if ( Part == PHY_PART_LOW )
        nNodeSizeMax += s_DynLowNodeSizeBonus;
    if ( nNodeSizeMax < 6 )
        nNodeSizeMax = 6;
    if ( nNodeSizeMax > 15 )
        nNodeSizeMax = 15;
    nConeSizeMax = nNodeSizeMax + 4;
    if ( nConeSizeMax > 15 )
        nConeSizeMax = 15;

    if ( SeqTemplate == 0 )
    {
        if ( nCutsMax < 20 )
            nCutsMax += 1;
    }
    else if ( SeqTemplate == 1 )
    {
        if ( nNodeSizeMax < 15 )
            nNodeSizeMax += 1;
        if ( nConeSizeMax < 15 )
            nConeSizeMax += 1;
    }
    else
    {
        if ( nCutsMax > 6 )
            nCutsMax -= 1;
        if ( nNodeSizeMax > 6 )
            nNodeSizeMax -= 1;
        if ( nConeSizeMax > nNodeSizeMax + 2 )
            nConeSizeMax = nNodeSizeMax + 2;
    }

    if ( Phy_RunSeqTemplateOps( pAbc, Part, SeqTemplate ) )
    {
        Abc_FrameReplaceCurrentNetwork( pAbc, pNtkBase );
        return 1;
    }

    pNtk = Abc_FrameReadNtk( pAbc );
    if ( pNtk == NULL || !Abc_NtkIsStrash(pNtk) )
    {
        Abc_FrameReplaceCurrentNetwork( pAbc, pNtkBase );
        return 1;
    }

    RetValue = Abc_NtkOrchLocal( pNtk, fUseZerosRwr, fUseZerosRef, fPlaceEnable,
        nCutsMax, nNodesMax, nLevelsOdc, fUpdateLevel, fVerbose, fVeryVerbose,
        nNodeSizeMax, nConeSizeMax, fUseDcs );

    if ( RetValue <= 0 )
    {
        Abc_FrameReplaceCurrentNetwork( pAbc, pNtkBase );
        return 1;
    }

    if ( !Phy_EnsureTmpDir() )
    {
        Abc_FrameReplaceCurrentNetwork( pAbc, pNtkBase );
        return 1;
    }

    snprintf( WinFile, sizeof(WinFile), "my_work/tmp/phyopt_win_tmp_%d.aig", nObjIdCenter );
    snprintf( Cmd, sizeof(Cmd), "write_aiger %s", WinFile );
    if ( Cmd_CommandExecute( pAbc, Cmd ) )
    {
        Abc_FrameReplaceCurrentNetwork( pAbc, pNtkBase );
        return 1;
    }
    fWinFileWritten = 1;

    Abc_FrameReplaceCurrentNetwork( pAbc, pNtkBase );
    pNtkBeforeIns = Abc_FrameReadNtk( pAbc );
    snprintf( Cmd, sizeof(Cmd), "inswin -N %d -D %d %s", nObjIdCenter, nRadius, WinFile );
    if ( Cmd_CommandExecute( pAbc, Cmd ) )
    {
        if ( fWinFileWritten )
            remove( WinFile );
        return 1;
    }
    pNtk = Abc_FrameReadNtk( pAbc );
    if ( pNtk == pNtkBeforeIns )
    {
        if ( fWinFileWritten )
            remove( WinFile );
        return 1;
    }
    if ( fWinFileWritten )
        remove( WinFile );
    return 0;
}

static int Phy_PctCount( int Total, int Pct )
{
    int C;
    if ( Total <= 0 )
        return 0;
    C = (Total * Pct + 99) / 100;
    if ( C < 1 ) C = 1;
    if ( C > Total ) C = Total;
    return C;
}

static float Phy_DynAnnealTemp( int RoundId )
{
    float Temp;
    int i;
    if ( !s_DynAnnealEnable )
        return s_DynAnnealMin;
    if ( RoundId < 0 )
        RoundId = 0;
    Temp = s_DynAnnealStart;
    for ( i = 0; i < RoundId; i++ )
        Temp *= s_DynAnnealDecay;
    if ( Temp < s_DynAnnealMin )
        Temp = s_DynAnnealMin;
    if ( Temp > s_DynAnnealStart )
        Temp = s_DynAnnealStart;
    return Temp;
}

static float Phy_DynAnnealScale01( float Temp )
{
    if ( s_DynAnnealStart <= s_DynAnnealMin + 1e-6f )
        return 0.0f;
    return Phy_ClampFloat( (Temp - s_DynAnnealMin) / (s_DynAnnealStart - s_DynAnnealMin), 0.0f, 1.0f );
}

static float Phy_PartScore( double AreaSum, double DelaySum, int AccSum, int RejSum, int Attempts )
{
    float AvgArea, AvgDelay, AccRate, DelayPen;
    if ( Attempts <= 0 )
        return 0.0f;
    AvgArea = (float)(AreaSum / (double)Attempts);
    AvgDelay = (float)(DelaySum / (double)Attempts);
    AccRate = (AccSum + RejSum) > 0 ? (float)AccSum / (float)(AccSum + RejSum) : 0.0f;
    DelayPen = AvgDelay > 0.0f ? AvgDelay * 10.0f : 0.0f;
    return AvgArea * AccRate - DelayPen;
}

static int Phy_PotBin( float Pot )
{
    int Bin = (int)(Pot * (float)PHY_DYN_ACC_BINS);
    if ( Bin < 0 )
        Bin = 0;
    if ( Bin >= PHY_DYN_ACC_BINS )
        Bin = PHY_DYN_ACC_BINS - 1;
    return Bin;
}

static float Phy_BinAcceptPrior(
    Phy_PartType_t Part,
    float Pot,
    const int TryBin[3][PHY_DYN_ACC_BINS],
    const int AccBin[3][PHY_DYN_ACC_BINS],
    const int DynAttempts[3],
    const int DynAcc[3] )
{
    int Bin = Phy_PotBin( Pot );
    float PartRate = (float)(DynAcc[Part] + 1) / (float)(DynAttempts[Part] + 2);
    float Hit = (float)AccBin[Part][Bin];
    float Tried = (float)TryBin[Part][Bin];
    float PriorK = s_DynAccPriorStrength;
    return (Hit + PriorK * PartRate) / (Tried + PriorK);
}

static float Phy_GlobalScore( const float * pPartScore )
{
    return (pPartScore[0] + pPartScore[1] + pPartScore[2]) / 3.0f;
}

static float Phy_L0Score(
    const Phy_NodeInfo_t * pSeed,
    Phy_PartType_t Part,
    const int TryBin[3][PHY_DYN_ACC_BINS],
    const int AccBin[3][PHY_DYN_ACC_BINS],
    const int DynAttempts[3],
    const int DynAcc[3] )
{
    float Pot = Phy_NodePartPotential( pSeed, Part );
    float Prior = Phy_BinAcceptPrior( Part, Pot, TryBin, AccBin, DynAttempts, DynAcc );
    return s_DynL0WPotential * Pot + s_DynL0WCriticality * pSeed->Criticality + s_DynL0WAccPrior * Prior;
}

static float Phy_L1EstimateReward(
    const Phy_NodeInfo_t * pSeed,
    Phy_PartType_t Part,
    int nWindowSize,
    const int TryBin[3][PHY_DYN_ACC_BINS],
    const int AccBin[3][PHY_DYN_ACC_BINS],
    const int DynAttempts[3],
    const int DynAcc[3] )
{
    float Pot = Phy_NodePartPotential( pSeed, Part );
    float Prior = Phy_BinAcceptPrior( Part, Pot, TryBin, AccBin, DynAttempts, DynAcc );
    float WindowNorm = (float)nWindowSize / 32.0f;
    float FanPenalty = (float)pSeed->Fanout / 12.0f;
    float DelayRisk = 0.60f * pSeed->Criticality + 0.25f * (1.0f - pSeed->SlackPotential) + 0.15f * FanPenalty;
    float AreaChance = 0.55f * Pot + s_DynL1WAccPrior * Prior + 0.10f * pSeed->StructPotential + 0.05f * WindowNorm;
    return AreaChance - s_DynL1WindowWeight * WindowNorm - s_DynL1DelayPenalty * DelayRisk;
}

static void Phy_L1UpdateThreshold( float * pThreshold, int L2TriedBatch, int L2AccBatch )
{
    float Curr, ObsAcc, Raw, Next;
    if ( pThreshold == NULL || L2TriedBatch <= 0 )
        return;
    Curr = *pThreshold;
    ObsAcc = (float)L2AccBatch / (float)L2TriedBatch;
    Raw = Curr + s_DynL1AdaptLr * (s_DynL1TargetAccept - ObsAcc);
    Raw = Phy_ClampFloat( Raw, s_DynL1ThresholdMin, s_DynL1ThresholdMax );
    Next = (1.0f - s_DynL1SmoothBeta) * Curr + s_DynL1SmoothBeta * Raw;
    *pThreshold = Phy_ClampFloat( Next, s_DynL1ThresholdMin, s_DynL1ThresholdMax );
}

static int Phy_ProcessSeedAttempt(
    Abc_Frame_t * pAbc,
    Phy_Data_t * pRoundData,
    Phy_NodeInfo_t * pSeed,
    Phy_PartType_t Part,
    int nWindowSize,
    int nMaxObjId,
    unsigned char * pMarked,
    Vec_Ptr_t * vMarkedNames,
    int fIsTopPot,
    int fVerbose,
    int * pnAccepted,
    int * pnRejected,
    int * pnSkippedMarked,
    int * pnSkippedLowSlack,
    int * pTriedPart,
    int * pAcceptedPart,
    int * pSkippedMarkedPart,
    int * pSkippedLowSlackPart,
    int * pTopPotTriedPart,
    int * pTopPotAcceptedPart,
    int * pRejectReason,
    int * pfTried,
    int * pfAccepted,
    int * pfGoalHit,
    int * pfEffectiveImprove,
    double * pAreaImprPct,
    double * pDelayDelta )
{
    Abc_Ntk_t * pNtk;
    Abc_Ntk_t * pNtkBak;
    int fAccept;
    int fQoROkBefore, fQoROkAfter;
    int nCenterId, nRadius, SeqTemplate;
    Phy_QoR_t QoRBefore, QoRAfter;

    *pfTried = 0;
    *pfAccepted = 0;
    *pfGoalHit = 0;
    *pfEffectiveImprove = 0;
    *pAreaImprPct = 0.0;
    *pDelayDelta = 0.0;

    if ( pSeed->ObjId >= 0 && pSeed->ObjId <= nMaxObjId && pMarked[pSeed->ObjId] )
    {
        (*pnSkippedMarked)++;
        pSkippedMarkedPart[Part]++;
        return 0;
    }
    if ( Phy_MarkedNameHas( vMarkedNames, pSeed->NodeName ) )
    {
        (*pnSkippedMarked)++;
        pSkippedMarkedPart[Part]++;
        return 0;
    }
    if ( Part == PHY_PART_LOW && pSeed->Slack < s_DynLowSkipSlackMin )
    {
        (*pnSkippedLowSlack)++;
        pSkippedLowSlackPart[Part]++;
        return 0;
    }

    pNtk = Abc_FrameReadNtk( pAbc );
    if ( pNtk == NULL )
        return 1;

    fQoROkBefore = Phy_EvalMappedQoR( pNtk, &QoRBefore );
    if ( !fQoROkBefore )
    {
        if ( fVerbose )
            Abc_Print( 1, "phyopt: skip seed=%s (cannot evaluate mapped QoR before optimization).\n", pSeed->NodeName );
        (*pnRejected)++;
        pRejectReason[0]++;
        return 0;
    }

    nCenterId = Phy_GetWindowCenterObjId( pNtk, pSeed );
    nRadius = Phy_WindowRadius( pSeed, Part, nWindowSize );
    SeqTemplate = Phy_SeqSelectTemplate( Part, pSeed );
    if ( nCenterId <= 0 )
    {
        if ( fVerbose )
            Abc_Print( 1, "phyopt: skip seed=%s (cannot resolve center node in current AIG).\n", pSeed->NodeName );
        (*pnRejected)++;
        pRejectReason[0]++;
        return 0;
    }

    pNtkBak = Abc_NtkDup( pNtk );
    if ( pNtkBak == NULL )
        return 1;

    pTriedPart[Part]++;
    if ( fIsTopPot )
        pTopPotTriedPart[Part]++;
    if ( fVerbose )
        Abc_Print( 1, "phyopt: part=%s seed=%s(id=%d center=%d R=%d tpl=%d crit=%.3f pot=%.4f)\n",
            Phy_PartName( Part ),
            pSeed->NodeName, pSeed->ObjId, nCenterId, nRadius, SeqTemplate, pSeed->Criticality,
            Phy_NodePartPotential( pSeed, Part ) );

    *pfTried = 1;

    if ( Phy_OptWindowPass( pAbc, pSeed, Part, nWindowSize, nCenterId, nRadius, SeqTemplate ) )
    {
        Abc_Print( -1, "phyopt: local optimization failed. Rolling back.\n" );
        Abc_FrameReplaceCurrentNetwork( pAbc, pNtkBak );
        (*pnRejected)++;
        pRejectReason[0]++;
        Phy_SeqRecordTemplate( Part, SeqTemplate, 0 );
        return 0;
    }

    pNtk = Abc_FrameReadNtk( pAbc );
    fQoROkAfter = Phy_EvalMappedQoR( pNtk, &QoRAfter );
    if ( !fQoROkAfter )
    {
        Abc_FrameReplaceCurrentNetwork( pAbc, pNtkBak );
        (*pnRejected)++;
        pRejectReason[0]++;
        Phy_SeqRecordTemplate( Part, SeqTemplate, 0 );
        return 0;
    }

    *pAreaImprPct = (QoRBefore.Area > 0.0) ? ((QoRBefore.Area - QoRAfter.Area) * 100.0 / QoRBefore.Area) : 0.0;
    *pDelayDelta = QoRAfter.Delay - QoRBefore.Delay;
    if ( Phy_QorGoalHit( QoRBefore, QoRAfter ) )
        *pfGoalHit = 1;
    if ( *pAreaImprPct >= 0.05 && *pDelayDelta <= 0.0 )
        *pfEffectiveImprove = 1;

    fAccept = Phy_AcceptByMappedQoR( Part, QoRBefore, QoRAfter );
    if ( fAccept )
    {
        Abc_NtkDelete( pNtkBak );
        pAcceptedPart[Part]++;
        (*pnAccepted)++;
        *pfAccepted = 1;
        if ( fIsTopPot )
            pTopPotAcceptedPart[Part]++;
        if ( fVerbose )
            Abc_Print( 1, "phyopt: accepted (map area %.2f->%.2f, delay %.2f->%.2f).\n",
                QoRBefore.Area, QoRAfter.Area, QoRBefore.Delay, QoRAfter.Delay );
        Phy_MarkAffectedAccepted( pMarked, nMaxObjId, vMarkedNames, pSeed, pRoundData );
        Phy_SeqRecordTemplate( Part, SeqTemplate, 1 );
    }
    else
    {
        Abc_FrameReplaceCurrentNetwork( pAbc, pNtkBak );
        (*pnRejected)++;
        pRejectReason[Phy_ClassifyMappedReject( Part, QoRBefore, QoRAfter )]++;
        if ( fVerbose )
            Abc_Print( 1, "phyopt: rejected (map area %.2f->%.2f, delay %.2f->%.2f).\n",
                QoRBefore.Area, QoRAfter.Area, QoRBefore.Delay, QoRAfter.Delay );
        Phy_SeqRecordTemplate( Part, SeqTemplate, 0 );
    }
    return 0;
}

int Phy_OptRun( Abc_Frame_t * pAbc, Phy_Data_t * pData, int nRounds, int nTop, int fVerbose, int fDynamicOrder, int nCaseTimeoutSec )
{
    Abc_Ntk_t * pNtk;
    Vec_Ptr_t * vMarkedNames;
    Phy_MicroModel_t MicroModel;
    int i, p, r, nAccepted = 0, nRejected = 0;
    int nWindowSize;
    abctime nTimeToStop = 0;
    int fTimeout = 0;
    int nTriedPart[3] = {0,0,0};
    int nAcceptedPart[3] = {0,0,0};
    int nSeedTotalPart[3] = {0,0,0};
    int nSkippedMarkedPart[3] = {0,0,0};
    int nSkippedLowSlackPart[3] = {0,0,0};
    int nTopPotTotalPart[3] = {0,0,0};
    int nTopPotTriedPart[3] = {0,0,0};
    int nTopPotAcceptedPart[3] = {0,0,0};
    int nRejectReason[6] = {0,0,0,0,0,0};
    int nSkippedMarked = 0, nSkippedLowSlack = 0;
    const Phy_PartType_t Order[3] = { PHY_PART_HIGH, PHY_PART_LOW, PHY_PART_MID };

    if ( pAbc == NULL || pData == NULL )
        return 1;

    pNtk = Abc_FrameReadNtk( pAbc );
    if ( pNtk == NULL )
    {
        Abc_Print( -1, "phyopt: no current network. Please read an AIG before optimization.\n" );
        return 1;
    }

    if ( Cmd_CommandExecute( pAbc, "strash" ) )
    {
        Abc_Print( -1, "phyopt: failed to strash the current network.\n" );
        return 1;
    }

    if ( Vec_PtrSize( pData->vNodes ) <= 0 )
    {
        Abc_Print( -1, "phyopt: no physical nodes loaded.\n" );
        return 1;
    }
    nWindowSize = 16;
    if ( nTop > 0 && nTop < nWindowSize )
        nWindowSize = nTop;

    Phy_DynInitFromEnv();
    Phy_MicroModelInitFromEnv( &MicroModel );
    Phy_FitInitFromEnv();
    Phy_SeqStatsResetRun();
    if ( nCaseTimeoutSec <= 0 )
        nCaseTimeoutSec = Phy_GetEnvInt( "PHY_DYN_CASE_TIMEOUT_SEC", 0 );
    if ( nCaseTimeoutSec < 0 )
        nCaseTimeoutSec = 0;
    nTimeToStop = nCaseTimeoutSec ? ((abctime)nCaseTimeoutSec * CLOCKS_PER_SEC + Abc_Clock()) : 0;

    vMarkedNames = Vec_PtrAlloc( 1000 );
    if ( vMarkedNames == NULL )
    {
        Abc_Print( -1, "phyopt: out of memory for marked-node set.\n" );
        return 1;
    }

    if ( fVerbose )
    {
        Abc_Print( 1, "phyopt: start rounds=%d, criticality partitions high(>=%.3f)->low(<=%.3f)->mid, window=%d, mode=%s.\n",
            nRounds, s_CritHigh, s_CritLow, nWindowSize, fDynamicOrder ? "dynamic" : "fixed" );
        Abc_Print( 1, "phyopt: objective=delay-non-regression + area minimization (delay_eps=%.4g rel_tol=%.4g area_eps=%.4g delay_only=%s).\n",
            s_QorDelayAbsEps, s_QorDelayRelTol, s_QorAreaEps, s_QorAcceptDelayOnly ? "on" : "off" );
        if ( fDynamicOrder )
            Abc_Print( 1, "phyopt: dynamic scheduler enabled (init=%d%%, leader=%d%%, probe=%d%%, part-stop=%d, global-stop=%d, L2=%s, L2-topk-init=%d, L2-topk-step=%d).\n",
                s_DynInitPct, s_DynLeaderPct, s_DynProbePct, s_DynPartStopTried, s_DynGlobalStopRounds,
                s_DynUseL2Gate ? "on" : "off", s_DynL2TopKInit, s_DynL2TopKStep );
        if ( fDynamicOrder )
            Abc_Print( 1, "phyopt: funnel L0=%s(keep=%d%%) L1=%s(init=%.3f target=%.2f warmup=%d min_try=%d).\n",
                s_DynEnableL0 ? "on" : "off", s_DynL0KeepPct,
                s_DynEnableL1 ? "on" : "off", s_DynL1InitThreshold, s_DynL1TargetAccept,
                s_DynL1WarmupSamples, s_DynL1MinTryWarmupPerPart );
        if ( fDynamicOrder )
            Abc_Print( 1, "phyopt: seq-template adaptive=%s warmup_per_part=%d (templates=%d).\n",
                s_SeqAdaptiveEnable ? "on" : "off", s_SeqWarmupPerPart, PHY_SEQ_TEMPLATE_NUM );
        if ( fDynamicOrder )
            Abc_Print( 1, "phyopt: anneal=%s(start=%.2f min=%.2f decay=%.3f keep_boost=%d l1_slack=%.3f).\n",
                s_DynAnnealEnable ? "on" : "off",
                s_DynAnnealStart, s_DynAnnealMin, s_DynAnnealDecay,
                s_DynAnnealKeepBoostPct, s_DynAnnealL1Slack );
        if ( fDynamicOrder )
            Abc_Print( 1, "phyopt: low-relax radius+%d cuts+%d nodes+%d nodeSize+%d slack_skip_min=%.3f funnel(l0_keep+%d%% l1_relax=%.3f l2_topk+%d).\n",
                s_DynLowRadiusBonus, s_DynLowCutsBonus, s_DynLowNodesBonus,
                s_DynLowNodeSizeBonus, s_DynLowSkipSlackMin,
                s_DynLowL0KeepBoostPct, s_DynLowL1Relax, s_DynLowL2TopKBonus );
        if ( nCaseTimeoutSec > 0 )
            Abc_Print( 1, "phyopt: case timeout enabled (%d sec).\n", nCaseTimeoutSec );
        Abc_Print( 1, "phyopt: fit-function %s (loaded=%s, samples=%d, l0_scale=%.2f, l1_scale=%.2f, coef_file=%s).\n",
            s_FitEnable ? "on" : "off",
            s_FitLoaded ? "yes" : "no",
            s_FitSampleCount,
            s_FitL0Scale,
            s_FitL1Scale,
            s_FitCoefFile[0] ? s_FitCoefFile : "<builtin>" );
        Abc_Print( 1, "phyopt: sample-log %s (keep_target=%d%% [%d%%,%d%%]).\n",
            MicroModel.LogFile[0] ? MicroModel.LogFile : "off",
            MicroModel.KeepTargetTryPct,
            MicroModel.KeepMinPct,
            MicroModel.KeepMaxPct );
    }

    for ( r = 0; r < nRounds; ++r )
    {
        Phy_Data_t * pRoundData;
        Vec_Ptr_t * vHigh, * vLow, * vMid;
        int nMaxObjId = 0;
        unsigned char * pMarked;

        if ( nTimeToStop && Abc_Clock() >= nTimeToStop )
        {
            fTimeout = 1;
            break;
        }

        pRoundData = (r == 0) ? pData : Phy_RefreshDataForRound( pAbc, pData, fVerbose );

        if ( pRoundData == NULL || Vec_PtrSize(pRoundData->vNodes) == 0 )
        {
            Abc_Print( -1, "phyopt: round %d data refresh failed. Stop iterative optimization.\n", r + 1 );
            break;
        }

        vHigh = Vec_PtrAlloc( 100 );
        vLow  = Vec_PtrAlloc( 100 );
        vMid  = Vec_PtrAlloc( 100 );
        if ( vHigh == NULL || vLow == NULL || vMid == NULL )
        {
            if ( vHigh ) Vec_PtrFree( vHigh );
            if ( vLow )  Vec_PtrFree( vLow );
            if ( vMid )  Vec_PtrFree( vMid );
            if ( pRoundData != pData )
                Phy_DataFree( pRoundData );
            Phy_MarkedNameFree( vMarkedNames );
            Abc_Print( -1, "phyopt: out of memory while creating partitions.\n" );
            return 1;
        }

        {
            Phy_NodeInfo_t * pInfo;
            Vec_PtrForEachEntry( Phy_NodeInfo_t *, pRoundData->vNodes, pInfo, i )
            {
                if ( pInfo->ObjId > nMaxObjId )
                    nMaxObjId = pInfo->ObjId;
                if ( Phy_NodePart(pInfo) == PHY_PART_HIGH )
                    Vec_PtrPush( vHigh, pInfo );
                else if ( Phy_NodePart(pInfo) == PHY_PART_LOW )
                    Vec_PtrPush( vLow, pInfo );
                else
                    Vec_PtrPush( vMid, pInfo );
            }
        }

        pMarked = ABC_CALLOC( unsigned char, nMaxObjId + 1 );
        if ( pMarked == NULL )
        {
            Vec_PtrFree( vHigh );
            Vec_PtrFree( vLow );
            Vec_PtrFree( vMid );
            if ( pRoundData != pData )
                Phy_DataFree( pRoundData );
            Phy_MarkedNameFree( vMarkedNames );
            Abc_Print( -1, "phyopt: out of memory.\n" );
            return 1;
        }
        s_SortPart = PHY_PART_HIGH;
        qsort( vHigh->pArray, (size_t)Vec_PtrSize(vHigh), sizeof(void *), Phy_NodeCmpByPartPotential );
        s_SortPart = PHY_PART_LOW;
        qsort( vLow->pArray, (size_t)Vec_PtrSize(vLow), sizeof(void *), Phy_NodeCmpByPartPotential );
        s_SortPart = PHY_PART_MID;
        qsort( vMid->pArray, (size_t)Vec_PtrSize(vMid), sizeof(void *), Phy_NodeCmpByPartPotential );

        if ( fVerbose )
            Abc_Print( 1, "phyopt: round=%d partition sizes high=%d low=%d mid=%d.\n", r + 1, Vec_PtrSize(vHigh), Vec_PtrSize(vLow), Vec_PtrSize(vMid) );

        if ( !fDynamicOrder )
        {
            for ( p = 0; p < 3 && !fTimeout; ++p )
            {
                Vec_Ptr_t * vPart = (Order[p] == PHY_PART_HIGH) ? vHigh : (Order[p] == PHY_PART_LOW ? vLow : vMid);
                int nProcess = Vec_PtrSize( vPart );
                int nTopPotCut;
                if ( nTop > 0 && nProcess > nTop )
                    nProcess = nTop;
                nTopPotCut = nProcess < 5 ? nProcess : 5;
                nSeedTotalPart[Order[p]] += nProcess;
                nTopPotTotalPart[Order[p]] += nTopPotCut;
                for ( i = 0; i < nProcess; ++i )
                {
                    int fTried, fAcc, fGoal, fEff;
                    double AreaImpr, DelayDelta;
                    Phy_NodeInfo_t * pSeed = (Phy_NodeInfo_t *)Vec_PtrEntry( vPart, i );
                    if ( nTimeToStop && Abc_Clock() >= nTimeToStop )
                    {
                        fTimeout = 1;
                        break;
                    }
                    if ( Phy_ProcessSeedAttempt( pAbc, pRoundData, pSeed, Order[p], nWindowSize,
                        nMaxObjId, pMarked, vMarkedNames, (i < nTopPotCut), fVerbose,
                        &nAccepted, &nRejected, &nSkippedMarked, &nSkippedLowSlack,
                        nTriedPart, nAcceptedPart, nSkippedMarkedPart, nSkippedLowSlackPart,
                        nTopPotTriedPart, nTopPotAcceptedPart, nRejectReason,
                        &fTried, &fAcc, &fGoal, &fEff, &AreaImpr, &DelayDelta ) )
                    {
                        Vec_PtrFree( vHigh );
                        Vec_PtrFree( vLow );
                        Vec_PtrFree( vMid );
                        if ( pRoundData != pData )
                            Phy_DataFree( pRoundData );
                        ABC_FREE( pMarked );
                        Phy_MarkedNameFree( vMarkedNames );
                        Abc_Print( -1, "phyopt: internal failure while processing seed.\n" );
                        return 1;
                    }
                }
            }
        }
        else
        {
            Vec_Ptr_t * vPartOf[3] = { vHigh, vLow, vMid };
            int Cursor[3] = {0, 0, 0};
            int Stopped[3] = {0, 0, 0};
            int NoImproveStreak[3] = {0, 0, 0};
            int DynAttempts[3] = {0, 0, 0};
            int DynAcc[3] = {0, 0, 0};
            int DynRej[3] = {0, 0, 0};
            int DynL2Skip[3] = {0, 0, 0};
            int DynL0Skip[3] = {0, 0, 0};
            int DynL1Skip[3] = {0, 0, 0};
            int DynTryBin[3][PHY_DYN_ACC_BINS] = {{0}};
            int DynAccBin[3][PHY_DYN_ACC_BINS] = {{0}};
            double DynAreaSum[3] = {0.0, 0.0, 0.0};
            double DynDelaySum[3] = {0.0, 0.0, 0.0};
            float PartScore[3] = {0.0f, 0.0f, 0.0f};
            float BestGlobalScore;
            int NoGlobalImproveRounds = 0;
            float L1Threshold = s_DynL1InitThreshold;
            float RoundTemp = Phy_DynAnnealTemp( r );
            float RoundExploreScale = Phy_DynAnnealScale01( RoundTemp );
            int L1SeenTotal = 0;
            int KeepPctPart[3] = {
                Phy_ClampAtLeastOne( s_DynL0KeepPct, 99 ),
                Phy_ClampAtLeastOne( s_DynL0KeepPct, 99 ),
                Phy_ClampAtLeastOne( s_DynL0KeepPct, 99 )
            };

            for ( p = 0; p < 3 && !fTimeout; ++p )
            {
                int Part = Order[p];
                int SizePart = Vec_PtrSize( vPartOf[Part] );
                int InitCnt = Phy_PctCount( SizePart, s_DynInitPct );
                int BatchSeen[3] = {0, 0, 0};
                int BatchTried[3] = {0, 0, 0};
                int BatchEff[3] = {0, 0, 0};
                int L2CapPart[3] = {0, 0, 0};
                int L2EnteredPart[3] = {0, 0, 0};
                int L2TriedBatch = 0, L2AccBatch = 0;
                int iCand;
                Vec_Ptr_t * vBatch = Vec_PtrAlloc( 64 );
                nSeedTotalPart[Part] += SizePart;
                nTopPotTotalPart[Part] += (InitCnt < 5 ? InitCnt : 5);
                if ( SizePart == 0 )
                {
                    Stopped[Part] = 1;
                    Vec_PtrFree( vBatch );
                    continue;
                }

                for ( iCand = 0; iCand < 3; ++iCand )
                {
                    int Part2 = Order[iCand];
                    int SizePart2 = Vec_PtrSize( vPartOf[Part2] );
                    int SeenNow = 0;
                    int Cnt = (Part2 == Part) ? InitCnt : 0;
                    int L2CapBase = s_DynL2TopKInit;
                    if ( Part2 == PHY_PART_LOW )
                        L2CapBase += s_DynLowL2TopKBonus;
                    L2CapPart[Part2] = Phy_ClampAtLeastOne( L2CapBase, Cnt );
                    while ( Cursor[Part2] < SizePart2 && SeenNow < Cnt )
                    {
                        Phy_BatchCand_t * pCand = ABC_CALLOC( Phy_BatchCand_t, 1 );
                        pCand->Part = (Phy_PartType_t)Part2;
                        pCand->pSeed = (Phy_NodeInfo_t *)Vec_PtrEntry( vPartOf[Part2], Cursor[Part2]++ );
                        pCand->fTopPot = (Cursor[Part2] <= 5);
                        pCand->L0Score = Phy_L0Score( pCand->pSeed, pCand->Part, DynTryBin, DynAccBin, DynAttempts, DynAcc );
                        pCand->PriorScore = Phy_BinAcceptPrior( pCand->Part, Phy_NodePartPotential( pCand->pSeed, pCand->Part ), DynTryBin, DynAccBin, DynAttempts, DynAcc );
                        Phy_MicroBuildFeatures( pCand->pSeed, pCand->Part, nWindowSize, pCand->PriorScore, pCand->Feat );
                        pCand->ModelProb = Phy_FitPredict( pCand->Feat );
                        pCand->RankScore = Phy_FitBlendL0( pCand->L0Score, pCand->ModelProb );
                        Vec_PtrPush( vBatch, pCand );
                        SeenNow++;
                        BatchSeen[Part2]++;
                    }
                }

                if ( Vec_PtrSize(vBatch) > 0 )
                {
                    int KeepCntPart[3] = {0, 0, 0};
                    int PassCntPart[3] = {0, 0, 0};
                    qsort( vBatch->pArray, (size_t)Vec_PtrSize(vBatch), sizeof(void *), Phy_BatchCandCmpByL0Desc );
                    for ( iCand = 0; iCand < 3; ++iCand )
                    {
                        int BasePct = s_DynEnableL0 ? KeepPctPart[iCand] : 100;
                        int AnnealBoost = (int)(RoundExploreScale * (float)s_DynAnnealKeepBoostPct + 0.5f);
                        int ExplorePct = (int)(100.0f * MicroModel.ExploreFloor + 0.5f);
                        if ( iCand == PHY_PART_LOW )
                            BasePct += s_DynLowL0KeepBoostPct;
                        BasePct += AnnealBoost;
                        if ( DynAttempts[iCand] < (int)MicroModel.TrustSamples && BasePct < ExplorePct )
                            BasePct = ExplorePct;
                        if ( BasePct < 1 ) BasePct = 1;
                        if ( BasePct > 100 ) BasePct = 100;
                        KeepCntPart[iCand] = Phy_PctCount( BatchSeen[iCand], BasePct );
                    }
                    for ( iCand = 0; iCand < Vec_PtrSize(vBatch); ++iCand )
                    {
                        Phy_BatchCand_t * pCand = (Phy_BatchCand_t *)Vec_PtrEntry( vBatch, iCand );
                        int Part2 = pCand->Part;
                        pCand->fL0Pass = (PassCntPart[Part2] < KeepCntPart[Part2]);
                        if ( pCand->fL0Pass )
                            PassCntPart[Part2]++;
                    }
                    if ( s_DynKeepAlivePerPart )
                    {
                        int PartBestIdx[3] = {-1, -1, -1};
                        for ( iCand = 0; iCand < Vec_PtrSize(vBatch); ++iCand )
                        {
                            Phy_BatchCand_t * pCand = (Phy_BatchCand_t *)Vec_PtrEntry( vBatch, iCand );
                            if ( PartBestIdx[pCand->Part] < 0 )
                                PartBestIdx[pCand->Part] = iCand;
                        }
                        for ( iCand = 0; iCand < 3; ++iCand )
                            if ( PartBestIdx[iCand] >= 0 )
                                ((Phy_BatchCand_t *)Vec_PtrEntry(vBatch, PartBestIdx[iCand]))->fL0Pass = 1;
                    }

                    for ( iCand = 0; iCand < Vec_PtrSize(vBatch); ++iCand )
                    {
                        int fTried, fAcc, fGoal, fEff;
                        double AreaImpr, DelayDelta;
                        Phy_BatchCand_t * pCand = (Phy_BatchCand_t *)Vec_PtrEntry( vBatch, iCand );
                        int Part2 = pCand->Part;
                        if ( !pCand->fL0Pass )
                        {
                            DynL0Skip[Part2]++;
                            continue;
                        }
                        pCand->L1Score = Phy_L1EstimateReward( pCand->pSeed, pCand->Part, nWindowSize, DynTryBin, DynAccBin, DynAttempts, DynAcc );
                        pCand->L1Score = Phy_FitBlendL1( pCand->L1Score, pCand->ModelProb );
                        L1SeenTotal++;
                        if ( s_DynEnableL1 && L1SeenTotal > s_DynL1WarmupSamples && DynAttempts[Part2] >= s_DynL1MinTryWarmupPerPart )
                        {
                            float L1Gate = L1Threshold - RoundExploreScale * s_DynAnnealL1Slack;
                            if ( Part2 == PHY_PART_LOW )
                                L1Gate -= s_DynLowL1Relax;
                            if ( pCand->L1Score < L1Gate )
                            {
                                DynL1Skip[Part2]++;
                                continue;
                            }
                        }
                        if ( s_DynUseL2Gate && L2EnteredPart[Part2] >= L2CapPart[Part2] )
                        {
                            DynL2Skip[Part2]++;
                            continue;
                        }
                        L2EnteredPart[Part2]++;

                        if ( nTimeToStop && Abc_Clock() >= nTimeToStop )
                        {
                            fTimeout = 1;
                            break;
                        }

                        if ( Phy_ProcessSeedAttempt( pAbc, pRoundData, pCand->pSeed, pCand->Part, nWindowSize,
                            nMaxObjId, pMarked, vMarkedNames, pCand->fTopPot, fVerbose,
                            &nAccepted, &nRejected, &nSkippedMarked, &nSkippedLowSlack,
                            nTriedPart, nAcceptedPart, nSkippedMarkedPart, nSkippedLowSlackPart,
                            nTopPotTriedPart, nTopPotAcceptedPart, nRejectReason,
                            &fTried, &fAcc, &fGoal, &fEff, &AreaImpr, &DelayDelta ) )
                        {
                            int k;
                            for ( k = 0; k < Vec_PtrSize(vBatch); ++k )
                            {
                                void * pTmp = Vec_PtrEntry( vBatch, k );
                                ABC_FREE( pTmp );
                            }
                            Vec_PtrFree( vBatch );
                            Vec_PtrFree( vHigh );
                            Vec_PtrFree( vLow );
                            Vec_PtrFree( vMid );
                            if ( pRoundData != pData )
                                Phy_DataFree( pRoundData );
                            ABC_FREE( pMarked );
                            Phy_MarkedNameFree( vMarkedNames );
                            return 1;
                        }
                        if ( fTried )
                        {
                            Phy_MicroLogSample( &MicroModel, pCand->Part, pCand->pSeed, nWindowSize,
                                pCand->PriorScore, pCand->ModelProb, fAcc, fGoal, AreaImpr, DelayDelta );
                            BatchTried[Part2]++;
                            DynAttempts[Part2]++;
                            DynAreaSum[Part2] += AreaImpr;
                            DynDelaySum[Part2] += DelayDelta;
                            DynTryBin[Part2][Phy_PotBin( Phy_NodePartPotential( pCand->pSeed, pCand->Part ) )]++;
                            L2TriedBatch++;
                            if ( fAcc )
                            {
                                DynAcc[Part2]++;
                                DynAccBin[Part2][Phy_PotBin( Phy_NodePartPotential( pCand->pSeed, pCand->Part ) )]++;
                                L2AccBatch++;
                            }
                            else
                                DynRej[Part2]++;
                            if ( fEff ) BatchEff[Part2]++;
                        }
                    }

                    for ( iCand = 0; iCand < Vec_PtrSize(vBatch); ++iCand )
                    {
                        void * pTmp = Vec_PtrEntry( vBatch, iCand );
                        ABC_FREE( pTmp );
                    }
                }

                Vec_PtrFree( vBatch );
                if ( fTimeout )
                    break;
                for ( iCand = 0; iCand < 3; ++iCand )
                {
                    int Part2 = Order[iCand];
                    int SizePart2 = Vec_PtrSize( vPartOf[Part2] );
                    if ( BatchTried[Part2] > 0 )
                    {
                        if ( BatchEff[Part2] > 0 ) NoImproveStreak[Part2] = 0;
                        else NoImproveStreak[Part2] += BatchTried[Part2];
                        if ( NoImproveStreak[Part2] >= s_DynPartStopTried )
                            Stopped[Part2] = 1;
                    }
                    if ( Cursor[Part2] >= SizePart2 )
                        Stopped[Part2] = 1;
                    PartScore[Part2] = Phy_PartScore( DynAreaSum[Part2], DynDelaySum[Part2], DynAcc[Part2], DynRej[Part2], DynAttempts[Part2] );
                    if ( BatchSeen[Part2] > 0 )
                    {
                        int ObsTryPct = (100 * BatchTried[Part2] + (BatchSeen[Part2] / 2)) / BatchSeen[Part2];
                        if ( ObsTryPct + 2 < MicroModel.KeepTargetTryPct )
                            KeepPctPart[Part2] += MicroModel.KeepAdaptStepPct;
                        else if ( ObsTryPct > MicroModel.KeepTargetTryPct + 8 )
                            KeepPctPart[Part2] -= MicroModel.KeepAdaptStepPct;
                        if ( KeepPctPart[Part2] < MicroModel.KeepMinPct ) KeepPctPart[Part2] = MicroModel.KeepMinPct;
                        if ( KeepPctPart[Part2] > MicroModel.KeepMaxPct ) KeepPctPart[Part2] = MicroModel.KeepMaxPct;
                    }
                }
                Phy_L1UpdateThreshold( &L1Threshold, L2TriedBatch, L2AccBatch );
            }

            BestGlobalScore = Phy_GlobalScore( PartScore );

            while ( 1 )
            {
                int TopPart = -1;
                float TopScore = -1.0e20f;
                int AnyActive = 0;
                float GlobalScore;
                if ( nTimeToStop && Abc_Clock() >= nTimeToStop )
                {
                    fTimeout = 1;
                    break;
                }
                for ( p = 0; p < 3; ++p )
                {
                    int Part = Order[p];
                    int SizePart = Vec_PtrSize( vPartOf[Part] );
                    if ( !Stopped[Part] && Cursor[Part] < SizePart )
                    {
                        AnyActive = 1;
                        if ( TopPart < 0 || PartScore[Part] > TopScore )
                        {
                            TopPart = Part;
                            TopScore = PartScore[Part];
                        }
                    }
                }
                if ( !AnyActive || TopPart < 0 )
                    break;

                for ( p = 0; p < 3 && !fTimeout; ++p )
                {
                    int Part = Order[p];
                    int SizePart = Vec_PtrSize( vPartOf[Part] );
                    int StepPct = (Part == TopPart) ? s_DynLeaderPct : s_DynProbePct;
                    int ChunkCnt = Phy_PctCount( SizePart, StepPct );
                    int BatchSeen[3] = {0, 0, 0};
                    int BatchTried[3] = {0, 0, 0};
                    int BatchEff[3] = {0, 0, 0};
                    int L2CapPart[3] = {0, 0, 0};
                    int L2EnteredPart[3] = {0, 0, 0};
                    int L2TriedBatch = 0, L2AccBatch = 0;
                    int iCand;
                    Vec_Ptr_t * vBatch = Vec_PtrAlloc( 128 );
                    if ( Stopped[Part] || Cursor[Part] >= SizePart )
                    {
                        Vec_PtrFree( vBatch );
                        continue;
                    }

                    for ( iCand = 0; iCand < 3; ++iCand )
                    {
                        int Part2 = Order[iCand];
                        int SizePart2 = Vec_PtrSize( vPartOf[Part2] );
                        int Cnt = (Part2 == Part) ? ChunkCnt : 0;
                        int SeenNow = 0;
                        int L2CapBase = (Part2 == TopPart) ? s_DynL2TopKInit : s_DynL2TopKStep;
                        if ( Part2 == PHY_PART_LOW )
                            L2CapBase += s_DynLowL2TopKBonus;
                        L2CapPart[Part2] = Phy_ClampAtLeastOne( L2CapBase, Cnt );
                        while ( Cursor[Part2] < SizePart2 && SeenNow < Cnt )
                        {
                            Phy_BatchCand_t * pCand = ABC_CALLOC( Phy_BatchCand_t, 1 );
                            pCand->Part = (Phy_PartType_t)Part2;
                            pCand->pSeed = (Phy_NodeInfo_t *)Vec_PtrEntry( vPartOf[Part2], Cursor[Part2]++ );
                            pCand->fTopPot = 0;
                            pCand->L0Score = Phy_L0Score( pCand->pSeed, pCand->Part, DynTryBin, DynAccBin, DynAttempts, DynAcc );
                            pCand->PriorScore = Phy_BinAcceptPrior( pCand->Part, Phy_NodePartPotential( pCand->pSeed, pCand->Part ), DynTryBin, DynAccBin, DynAttempts, DynAcc );
                            Phy_MicroBuildFeatures( pCand->pSeed, pCand->Part, nWindowSize, pCand->PriorScore, pCand->Feat );
                            pCand->ModelProb = Phy_FitPredict( pCand->Feat );
                            pCand->RankScore = Phy_FitBlendL0( pCand->L0Score, pCand->ModelProb );
                            Vec_PtrPush( vBatch, pCand );
                            SeenNow++;
                            BatchSeen[Part2]++;
                        }
                    }

                    if ( Vec_PtrSize(vBatch) > 0 )
                    {
                        int KeepCntPart[3] = {0, 0, 0};
                        int PassCntPart[3] = {0, 0, 0};
                        qsort( vBatch->pArray, (size_t)Vec_PtrSize(vBatch), sizeof(void *), Phy_BatchCandCmpByL0Desc );
                        for ( iCand = 0; iCand < 3; ++iCand )
                        {
                            int BasePct = s_DynEnableL0 ? KeepPctPart[iCand] : 100;
                            int AnnealBoost = (int)(RoundExploreScale * (float)s_DynAnnealKeepBoostPct + 0.5f);
                            int ExplorePct = (int)(100.0f * MicroModel.ExploreFloor + 0.5f);
                            if ( iCand == PHY_PART_LOW )
                                BasePct += s_DynLowL0KeepBoostPct;
                            BasePct += AnnealBoost;
                            if ( DynAttempts[iCand] < (int)MicroModel.TrustSamples && BasePct < ExplorePct )
                                BasePct = ExplorePct;
                            if ( BasePct < 1 ) BasePct = 1;
                            if ( BasePct > 100 ) BasePct = 100;
                            KeepCntPart[iCand] = Phy_PctCount( BatchSeen[iCand], BasePct );
                        }
                        for ( iCand = 0; iCand < Vec_PtrSize(vBatch); ++iCand )
                        {
                            Phy_BatchCand_t * pCand = (Phy_BatchCand_t *)Vec_PtrEntry( vBatch, iCand );
                            int Part2 = pCand->Part;
                            pCand->fL0Pass = (PassCntPart[Part2] < KeepCntPart[Part2]);
                            if ( pCand->fL0Pass )
                                PassCntPart[Part2]++;
                        }
                        if ( s_DynKeepAlivePerPart )
                        {
                            int PartBestIdx[3] = {-1, -1, -1};
                            for ( iCand = 0; iCand < Vec_PtrSize(vBatch); ++iCand )
                            {
                                Phy_BatchCand_t * pCand = (Phy_BatchCand_t *)Vec_PtrEntry( vBatch, iCand );
                                if ( PartBestIdx[pCand->Part] < 0 )
                                    PartBestIdx[pCand->Part] = iCand;
                            }
                            for ( iCand = 0; iCand < 3; ++iCand )
                                if ( PartBestIdx[iCand] >= 0 )
                                    ((Phy_BatchCand_t *)Vec_PtrEntry(vBatch, PartBestIdx[iCand]))->fL0Pass = 1;
                        }

                        for ( iCand = 0; iCand < Vec_PtrSize(vBatch); ++iCand )
                        {
                            int fTried, fAcc, fGoal, fEff;
                            double AreaImpr, DelayDelta;
                            Phy_BatchCand_t * pCand = (Phy_BatchCand_t *)Vec_PtrEntry( vBatch, iCand );
                            int Part2 = pCand->Part;
                            if ( !pCand->fL0Pass )
                            {
                                DynL0Skip[Part2]++;
                                continue;
                            }
                            pCand->L1Score = Phy_L1EstimateReward( pCand->pSeed, pCand->Part, nWindowSize, DynTryBin, DynAccBin, DynAttempts, DynAcc );
                            pCand->L1Score = Phy_FitBlendL1( pCand->L1Score, pCand->ModelProb );
                            L1SeenTotal++;
                            if ( s_DynEnableL1 && L1SeenTotal > s_DynL1WarmupSamples && DynAttempts[Part2] >= s_DynL1MinTryWarmupPerPart )
                            {
                                float L1Gate = L1Threshold - RoundExploreScale * s_DynAnnealL1Slack;
                                if ( Part2 == PHY_PART_LOW )
                                    L1Gate -= s_DynLowL1Relax;
                                if ( pCand->L1Score < L1Gate )
                                {
                                    DynL1Skip[Part2]++;
                                    continue;
                                }
                            }
                            if ( s_DynUseL2Gate && L2EnteredPart[Part2] >= L2CapPart[Part2] )
                            {
                                DynL2Skip[Part2]++;
                                continue;
                            }
                            L2EnteredPart[Part2]++;

                            if ( nTimeToStop && Abc_Clock() >= nTimeToStop )
                            {
                                fTimeout = 1;
                                break;
                            }

                            if ( Phy_ProcessSeedAttempt( pAbc, pRoundData, pCand->pSeed, pCand->Part, nWindowSize,
                                nMaxObjId, pMarked, vMarkedNames, pCand->fTopPot, fVerbose,
                                &nAccepted, &nRejected, &nSkippedMarked, &nSkippedLowSlack,
                                nTriedPart, nAcceptedPart, nSkippedMarkedPart, nSkippedLowSlackPart,
                                nTopPotTriedPart, nTopPotAcceptedPart, nRejectReason,
                                &fTried, &fAcc, &fGoal, &fEff, &AreaImpr, &DelayDelta ) )
                            {
                                int k;
                                for ( k = 0; k < Vec_PtrSize(vBatch); ++k )
                                {
                                    void * pTmp = Vec_PtrEntry( vBatch, k );
                                    ABC_FREE( pTmp );
                                }
                                Vec_PtrFree( vBatch );
                                Vec_PtrFree( vHigh );
                                Vec_PtrFree( vLow );
                                Vec_PtrFree( vMid );
                                if ( pRoundData != pData )
                                    Phy_DataFree( pRoundData );
                                ABC_FREE( pMarked );
                                Phy_MarkedNameFree( vMarkedNames );
                                return 1;
                            }
                            if ( fTried )
                            {
                                Phy_MicroLogSample( &MicroModel, pCand->Part, pCand->pSeed, nWindowSize,
                                    pCand->PriorScore, pCand->ModelProb, fAcc, fGoal, AreaImpr, DelayDelta );
                                BatchTried[Part2]++;
                                DynAttempts[Part2]++;
                                DynAreaSum[Part2] += AreaImpr;
                                DynDelaySum[Part2] += DelayDelta;
                                DynTryBin[Part2][Phy_PotBin( Phy_NodePartPotential( pCand->pSeed, pCand->Part ) )]++;
                                L2TriedBatch++;
                                if ( fAcc )
                                {
                                    DynAcc[Part2]++;
                                    DynAccBin[Part2][Phy_PotBin( Phy_NodePartPotential( pCand->pSeed, pCand->Part ) )]++;
                                    L2AccBatch++;
                                }
                                else
                                    DynRej[Part2]++;
                                if ( fEff ) BatchEff[Part2]++;
                            }
                        }

                        for ( iCand = 0; iCand < Vec_PtrSize(vBatch); ++iCand )
                        {
                            void * pTmp = Vec_PtrEntry( vBatch, iCand );
                            ABC_FREE( pTmp );
                        }
                    }

                    Vec_PtrFree( vBatch );
                    if ( fTimeout )
                        break;
                    for ( iCand = 0; iCand < 3; ++iCand )
                    {
                        int Part2 = Order[iCand];
                        int SizePart2 = Vec_PtrSize( vPartOf[Part2] );
                        if ( BatchTried[Part2] > 0 )
                        {
                            if ( BatchEff[Part2] > 0 ) NoImproveStreak[Part2] = 0;
                            else NoImproveStreak[Part2] += BatchTried[Part2];
                            if ( NoImproveStreak[Part2] >= s_DynPartStopTried )
                                Stopped[Part2] = 1;
                        }
                        if ( Cursor[Part2] >= SizePart2 )
                            Stopped[Part2] = 1;
                        PartScore[Part2] = Phy_PartScore( DynAreaSum[Part2], DynDelaySum[Part2], DynAcc[Part2], DynRej[Part2], DynAttempts[Part2] );
                        if ( BatchSeen[Part2] > 0 )
                        {
                            int ObsTryPct = (100 * BatchTried[Part2] + (BatchSeen[Part2] / 2)) / BatchSeen[Part2];
                            if ( ObsTryPct + 2 < MicroModel.KeepTargetTryPct )
                                KeepPctPart[Part2] += MicroModel.KeepAdaptStepPct;
                            else if ( ObsTryPct > MicroModel.KeepTargetTryPct + 8 )
                                KeepPctPart[Part2] -= MicroModel.KeepAdaptStepPct;
                            if ( KeepPctPart[Part2] < MicroModel.KeepMinPct ) KeepPctPart[Part2] = MicroModel.KeepMinPct;
                            if ( KeepPctPart[Part2] > MicroModel.KeepMaxPct ) KeepPctPart[Part2] = MicroModel.KeepMaxPct;
                        }
                    }
                    Phy_L1UpdateThreshold( &L1Threshold, L2TriedBatch, L2AccBatch );
                }

                if ( fTimeout )
                    break;

                GlobalScore = Phy_GlobalScore( PartScore );
                if ( GlobalScore > BestGlobalScore + 1e-9f )
                {
                    BestGlobalScore = GlobalScore;
                    NoGlobalImproveRounds = 0;
                }
                else
                {
                    NoGlobalImproveRounds++;
                    if ( NoGlobalImproveRounds >= s_DynGlobalStopRounds )
                        break;
                }
            }

            if ( fVerbose && s_DynUseL2Gate )
                Abc_Print( 1, "phyopt: L2 skips high=%d low=%d mid=%d.\n", DynL2Skip[PHY_PART_HIGH], DynL2Skip[PHY_PART_LOW], DynL2Skip[PHY_PART_MID] );
            if ( fVerbose )
                Abc_Print( 1, "phyopt: L0/L1 skips high=%d/%d low=%d/%d mid=%d/%d, L1-threshold=%.4f, anneal_temp=%.3f.\n",
                    DynL0Skip[PHY_PART_HIGH], DynL1Skip[PHY_PART_HIGH],
                    DynL0Skip[PHY_PART_LOW], DynL1Skip[PHY_PART_LOW],
                    DynL0Skip[PHY_PART_MID], DynL1Skip[PHY_PART_MID], L1Threshold, RoundTemp );
            if ( fVerbose )
                Abc_Print( 1, "phyopt: adaptive keep high/low/mid=%d%%/%d%%/%d%%.\n",
                    KeepPctPart[PHY_PART_HIGH], KeepPctPart[PHY_PART_LOW], KeepPctPart[PHY_PART_MID] );
        }

        if ( fVerbose )
            Abc_Print( 1, "phyopt: finished round %d/%d.\n", r + 1, nRounds );

        Vec_PtrFree( vHigh );
        Vec_PtrFree( vLow );
        Vec_PtrFree( vMid );
        ABC_FREE( pMarked );
        if ( pRoundData != pData )
            Phy_DataFree( pRoundData );
        if ( fTimeout )
            break;
    }

    if ( fTimeout )
        Abc_Print( 1, "phyopt: case timeout reached, stop after current accepted network.\n" );

    pNtk = Abc_FrameReadNtk( pAbc );
    if ( pNtk != NULL && fVerbose )
    {
        int iPart;
        const char * pPartName[3] = { "high", "low", "mid" };
        const char * pReasonName[6] = {
            "runtime_or_eval_fail",
            "policy_tradeoff_reject",
            "delay_worse",
            "area_worse",
            "area_and_delay_worse",
            "delay_guard_violation"
        };
        Abc_Print( 1, "phyopt: partition summary (tried/accepted):\n" );
        Abc_Print( 1, "  high : %d / %d\n", nAcceptedPart[PHY_PART_HIGH], nTriedPart[PHY_PART_HIGH] );
        Abc_Print( 1, "  low  : %d / %d\n", nAcceptedPart[PHY_PART_LOW],  nTriedPart[PHY_PART_LOW]  );
        Abc_Print( 1, "  mid  : %d / %d\n", nAcceptedPart[PHY_PART_MID],  nTriedPart[PHY_PART_MID]  );
        Abc_Print( 1, "phyopt: per-part seed coverage (topK means top-5 potential within processed seeds):\n" );
        for ( iPart = 0; iPart < 3; iPart++ )
        {
            float TryRate = nSeedTotalPart[iPart] ? (100.0f * (float)nTriedPart[iPart] / (float)nSeedTotalPart[iPart]) : 0.0f;
            float AccRate = nTriedPart[iPart] ? (100.0f * (float)nAcceptedPart[iPart] / (float)nTriedPart[iPart]) : 0.0f;
            float TopHitRate = nTopPotTriedPart[iPart] ? (100.0f * (float)nTopPotAcceptedPart[iPart] / (float)nTopPotTriedPart[iPart]) : 0.0f;
            Abc_Print( 1, "  %s: seeds=%d tried=%d(%.1f%%) accepted=%d(%.1f%%) skipped(marked=%d,low_slack=%d) topK(tried=%d/%d accepted=%d hit=%.1f%%)\n",
                pPartName[iPart], nSeedTotalPart[iPart], nTriedPart[iPart], TryRate,
                nAcceptedPart[iPart], AccRate,
                nSkippedMarkedPart[iPart], nSkippedLowSlackPart[iPart],
                nTopPotTriedPart[iPart], nTopPotTotalPart[iPart], nTopPotAcceptedPart[iPart], TopHitRate );
        }
            Abc_Print( 1, "phyopt: sequence template stats by partition (template_id: accepted/tried):\n" );
            for ( iPart = 0; iPart < 3; iPart++ )
            {
                Abc_Print( 1, "  %s: t0=%d/%d t1=%d/%d t2=%d/%d\n",
                pPartName[iPart],
                s_SeqAccRun[iPart][0], s_SeqTryRun[iPart][0],
                s_SeqAccRun[iPart][1], s_SeqTryRun[iPart][1],
                s_SeqAccRun[iPart][2], s_SeqTryRun[iPart][2] );
            }
        Abc_Print( 1, "phyopt: rejection reason breakdown:\n" );
        for ( iPart = 0; iPart < 6; iPart++ )
            Abc_Print( 1, "  - %s : %d\n", pReasonName[iPart], nRejectReason[iPart] );
        Abc_Print( 1, "phyopt: skipped marked=%d low_slack=<0.10=%d\n", nSkippedMarked, nSkippedLowSlack );
        Abc_Print( 1, "phyopt: done, accepted=%d rejected=%d final_nodes=%d final_levels=%d.\n", nAccepted, nRejected, Abc_NtkNodeNum(pNtk), Abc_NtkLevel(pNtk) );
    }

    Phy_MarkedNameFree( vMarkedNames );
    return 0;
}

ABC_NAMESPACE_IMPL_END
