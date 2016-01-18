//
// <copyright file="GPUMatrixCUDAKernels.cpp" company="Microsoft">
//     Copyright (c) Microsoft Corporation.  All rights reserved.
// </copyright>
//

#include "BestGpu.h"

#ifndef CPUONLY

#include <float.h>
#include <cuda_runtime.h>
#include "CommonMatrix.h"
#include "device_functions.h"


#ifndef LONG64  //we would like to use 64-bit long to support large matrices. However, CUDA seems to support only 32-bit long
#define LONG64  long
#endif

#define IDX2C(i,j,ld) (((j)*(ld))+(i)) // 0 based indexing
#define threadsPerBlock 512

// Predefine this for later.
static __inline__ __device__ double atomicAdd(double* address, double val);
//CUDA Kernels code
template<class ElemType>
__global__ void _elementWisePowerOnCuda(
    ElemType alpha,     
    const ElemType *a, 
    ElemType* c,    
    const LONG64 N)
{
    LONG64 id = blockDim.x * blockIdx.x + threadIdx.x;
    if (id>=N)
        return;
    if (alpha==0)
    {
        c[id]=1;
    }
    else if (alpha==1)
    {
        c[id]=a[id];
    }
    else if (alpha==2)
    {
        c[id]=a[id]*a[id];
    }
    else if (alpha==3)
    {
        c[id]=a[id]*a[id]*a[id];
    }
    else
    {
        if (sizeof(ElemType)==sizeof(double))
        {
            c[id]=pow(a[id],alpha);
        }
        else
        {
            c[id]=powf(a[id],alpha);
        }
    }    
};

template<class ElemType>
__global__ void _inplaceSigmoidOnCuda(    
    ElemType* c,    
    const LONG64 N)
{
    LONG64 id = blockDim.x * blockIdx.x + threadIdx.x;
    if (id>=N)
        return;
    if (sizeof(ElemType)==sizeof(double))
    {
        if (c[id]>=0)
        {
            double e = exp(-1*c[id]);
            c[id]=1/(1+e);
        }
        else
        {
            double e = exp(c[id]);
            c[id]=e/(1+e);
        }
    }
    else
    {
        if (c[id]>=0)
        {
            float e = expf(-1*c[id]);
            c[id]=1/(1+e);
        }
        else
        {
            float e = exp(c[id]);
            c[id]=e/(1+e);
        }
    }
};

template<class ElemType>
__global__ void _assignSigmoidOf(    
    const ElemType* a,
    ElemType* res,    
    const LONG64 N)
{
    LONG64 id = blockDim.x * blockIdx.x + threadIdx.x;
    if (id>=N)
        return;
    if (sizeof(ElemType)==sizeof(double))
    {
        if (a[id]>=0)
        {
            double e = exp(-1*a[id]);
            res[id]=1/(1+e);
        }
        else
        {
            double e = exp(a[id]);
            res[id]=e/(1+e);
        }
    }
    else
    {
        if (a[id]>=0)
        {
            float e = expf(-1*a[id]);
            res[id]=1/(1+e);
        }
        else
        {
            float e = exp(a[id]);
            res[id]=e/(1+e);
        }
    }
};

template<class ElemType>
__global__ void _inplaceLinRectDerivative(    
    ElemType* c,    
    const LONG64 N)
{
    LONG64 id = blockDim.x * blockIdx.x + threadIdx.x;
    if (id>=N)
        return;
    if (c[id]<=0)
        c[id]=0;
    else
        c[id]=1;
}

template<class ElemType>
__global__ void _assignSigmoidDerivative( 
    ElemType *a,
    ElemType *c,
    LONG64 N)
{
    LONG64 id = blockDim.x * blockIdx.x + threadIdx.x;
    if (id>=N)
        return;
    c[id] = a[id] * (1-a[id]);
}

template<class ElemType>
__global__ void _inplaceTanhOnCuda(    
    ElemType* c,    
    const LONG64 N)
{
    LONG64 id = blockDim.x * blockIdx.x + threadIdx.x;
    if (id>=N)
        return;
    if (sizeof(ElemType)==sizeof(double))
    {
        c[id]=tanh(c[id]);
    }
    else
    {
        c[id]=tanhf(c[id]);
    }

};

//to prevent negative values caused by floating operations, we force inputs to be >=0
//this may, however, hide problems in the caller.
template<class ElemType>
__global__ void _inplaceSqrtOnCuda(    
    ElemType* c,    
    const LONG64 N)
{
    LONG64 id = blockDim.x * blockIdx.x + threadIdx.x;
    if (id>=N)
        return;
    if (sizeof(ElemType)==sizeof(double))
    {
        c[id]=sqrt(max((ElemType)0, c[id]));
    }
    else
    {
        c[id]=sqrtf(max(ElemType(0), c[id]));
    }
};

template<class ElemType>
__global__ void _inplaceExpOnCuda(    
    ElemType* c,    
    const LONG64 N)
{
    LONG64 id = blockDim.x * blockIdx.x + threadIdx.x;
    if (id>=N)
        return;
    if (sizeof(ElemType)==sizeof(double))
    {
        c[id]=exp(c[id]);
    }
    else
    {
        c[id]=expf(c[id]);
    }
};

template<class ElemType>
__global__ void _inplaceLogOnCuda(    
    ElemType* c,    
    const LONG64 N)
{
    LONG64 id = blockDim.x * blockIdx.x + threadIdx.x;
    if (id>=N)
        return;
    if (c[id]<EPS_IN_LOG)
    {
        c[id]=LOG_OF_EPS_IN_LOG;
    }
    else
    {
        if (sizeof(ElemType)==sizeof(double))
        {
            c[id]=log(c[id]);
        }
        else
        {
            c[id]=logf(c[id]);
        }
    }
};

template<class ElemType>
__global__ void _inplaceAbsOnCuda(    
    ElemType* c,    
    const LONG64 N)
{
    LONG64 id = blockDim.x * blockIdx.x + threadIdx.x;
    if (id>=N)
        return;
    if (sizeof(ElemType)==sizeof(double))
    {
        c[id]=fabs(c[id]);
    }
    else
    {
        c[id]=fabsf(c[id]);
    }
};

template<class ElemType>
__global__ void _inplaceCosineOnCuda(    
    ElemType* c,    
    const LONG64 N)
{
    LONG64 id = blockDim.x * blockIdx.x + threadIdx.x;
    if (id>=N)
        return;
    if (sizeof(ElemType)==sizeof(double))
    {
        c[id]=cos(c[id]);
    }
    else
    {
        c[id]=cosf(c[id]);
    }
};

template<class ElemType>
__global__ void _inplaceNegativeSineOnCuda(    
    ElemType* c,    
    const LONG64 N)
{
    LONG64 id = blockDim.x * blockIdx.x + threadIdx.x;
    if (id>=N)
        return;
    if (sizeof(ElemType)==sizeof(double))
    {
        c[id]=-sin(c[id]);
    }
    else
    {
        c[id]=-sinf(c[id]);
    }
};


template<class ElemType>
__global__ void _setValue(    
    ElemType* a,
    const ElemType v,
    const LONG64 N)
{
    LONG64 id = blockDim.x * blockIdx.x + threadIdx.x;
    if (id>=N)
        return;
    a[id]=v;
};

template<class ElemType>
__global__ void _setValue(    
    ElemType* a,
    const ElemType* d_v,
    const LONG64 N)
{
    LONG64 id = blockDim.x * blockIdx.x + threadIdx.x;
    if (id>=N)
        return;
    a[id]=d_v[0];
};

template<class ElemType>
__global__ void _assignRowSliceValuesOf(ElemType * dest, ElemType * src, const LONG64 N, const long startIndex, const long destRows, const long srcRows)
{
    LONG64 id = blockDim.x * blockIdx.x + threadIdx.x;
    if (id>=N)
        return;

    long col = id / destRows;
    long row = id - (col * destRows);

    //dest[id] = src[col*srcRows + row + startIndex];
    dest[id] = src[IDX2C(row + startIndex, col, srcRows)];
}

template<class ElemType>
__global__ void _addToRowSliceValuesOf(ElemType * dest, ElemType * src, const LONG64 N, const long startIndex, const long destRows, const long srcRows)
{
    LONG64 id = blockDim.x * blockIdx.x + threadIdx.x;
    if (id>=N)
        return;

    long col = id / srcRows;  //src is the full matrix, rowslice is taken from the dest
    long row = id - (col * srcRows);

    //dest[col*destRows + row + startIndex] += src[id];
    dest[IDX2C(row + startIndex, col, destRows)] += src[id];
}

template<class ElemType>
__global__ void _addWithRowSliceValuesOf(ElemType * dest, ElemType * src, const LONG64 N, const long startIndex, const long destRows, const long srcRows)
{
    LONG64 id = blockDim.x * blockIdx.x + threadIdx.x;
    if (id >= N)
        return;

    long col = id / destRows;  //dest is the full matrix, rowslice is taken from the src
    long row = id - (col * destRows);

    dest[id] += src[IDX2C(row + startIndex, col, srcRows)];
}

template<class ElemType>
__global__ void _assignRepeatOf(ElemType * dest, ElemType * src, const LONG64 N, const long srcRows, const long srcCols, const long destRows)
{
    LONG64 id = blockDim.x * blockIdx.x + threadIdx.x;
    if (id >= N)
        return;

    long destCol = id / destRows;
    long destRow = id - (destCol * destRows);

    long srcRow = destRow % srcRows;
    long srcCol = destCol % srcCols;

    dest[id] = src[IDX2C(srcRow,srcCol,srcRows)];
}

template<class ElemType>
__global__ void _assignPositiveAndShiftedNegSample(ElemType * dest, const ElemType * src, const LONG64 N, const long srcRows, const long srcCols, const long destRows, const long posNumber, const long shiftNumber)
{
    LONG64 id = blockDim.x * blockIdx.x + threadIdx.x;
    if (id >= N)
        return;

    long destCol = id / destRows;
    long destRow = id - (destCol * destRows);

    long sampleInDestCol = destRow / srcRows;
    long srcRow = destRow - srcRows * sampleInDestCol;
    long srcCol = sampleInDestCol < posNumber ? destCol : (destCol + shiftNumber + sampleInDestCol - posNumber) % srcCols;

    dest[id] = src[IDX2C(srcRow, srcCol, srcRows)];
}

template<class ElemType>
__global__ void _addFoldedPositiveAndShiftedNegSample(ElemType * folded, const ElemType * unfolded, const LONG64 unfoldedN, const long unfoldedRows, const long unfoldedCols, const long foldedRows, const long posNumber, const long shiftNumber)
{
    LONG64 id = blockDim.x * blockIdx.x + threadIdx.x;
    if (id >= unfoldedN)
        return;

    long unfoldedCol = id / unfoldedRows;
    long unfoldedRow = id - (unfoldedCol * unfoldedRows);

    long sampleInUnfoldedCol = unfoldedRow / foldedRows;
    long foldedRow = unfoldedRow - foldedRows * sampleInUnfoldedCol;
    long foldedCol = sampleInUnfoldedCol < posNumber ? unfoldedCol : (unfoldedCol + shiftNumber + sampleInUnfoldedCol - posNumber) % unfoldedCols;

    atomicAdd(&folded[IDX2C(foldedRow, foldedCol, foldedRows)], unfolded[id]);
}

template<class ElemType>
__global__ void _assignDifferenceOf1(
    ElemType* us,
    const ElemType alpha,
    const ElemType* a,
    const LONG64 N)
{
    LONG64 id = blockDim.x * blockIdx.x + threadIdx.x;
    if (id>=N)
        return;
    us[id]=alpha-a[id];
};

template<class ElemType>
__global__ void _assignDifferenceOf2(
    ElemType* us,
    const ElemType alpha,
    const ElemType* a,
    const LONG64 N)
{
    LONG64 id = blockDim.x * blockIdx.x + threadIdx.x;
    if (id>=N)
        return;
    us[id]=a[id]-alpha;
};

///a is a scalar
template<class ElemType>
__global__ void _scaleAndAddScalar(
    ElemType* c,
    const LONG64 N,
    const ElemType alpha,
    const ElemType* a
)
{
    LONG64 id = blockDim.x * blockIdx.x + threadIdx.x;
    if (id>=N)
        return;
    c[id] += alpha*a[0];
};

template<class ElemType>
__global__ void _addValue(    
    ElemType* a,
    const ElemType v,
    const LONG64 N)
{
    LONG64 id = blockDim.x * blockIdx.x + threadIdx.x;
    if (id>=N)
        return;
    a[id]+=v;
};

template<class ElemType>
__global__ void _addValue(    
    ElemType* a,
    const ElemType* d_v,
    const LONG64 N)
{
    LONG64 id = blockDim.x * blockIdx.x + threadIdx.x;
    if (id>=N)
        return;
    a[id]+=d_v[0];
};


template<class ElemType>
__global__ void _elemMul(    
    ElemType* a,
    const ElemType* b,
    const LONG64 N)
{
    LONG64 id = blockDim.x * blockIdx.x + threadIdx.x;
    if (id>=N)
        return;
    a[id]*=b[id];
};

template<class ElemType>
__global__ void _assignElementProductOf(
    ElemType* us,
    const ElemType* a,
    const ElemType* b,
    const LONG64 N)
{
    LONG64 id = blockDim.x * blockIdx.x + threadIdx.x;
    if (id>=N)
        return;
    us[id]=a[id]*b[id];
}

template<class ElemType>
__global__ void _assignKhatriRaoProductOf(
    ElemType* us,
    const ElemType* a,
    const ElemType* b,
    const long rowsA, 
    const long rowsB, 
    const long cols)
{
    LONG64 id = blockDim.x * blockIdx.x + threadIdx.x;

    const long rows = rowsA * rowsB;
    const long col = id / rows;
    if (col >= cols) 
        return; 

    const long row = id % rows;
    const long rowB = row / rowsA; 
    const long rowA = row % rowsA;

    us[id] = a[rowA + col * rowsA] * b[rowB + col * rowsB];
}

template<class ElemType>
__global__ void _addColumnReshapeProductOf(
    ElemType* us,
    const ElemType* a,
    const ElemType* b,
    const long rowsB, 
    const long rowsC, 
    const long cols,
    const bool transposeAColumn)
{
    LONG64 id = blockDim.x * blockIdx.x + threadIdx.x;

    const long col = id / rowsC;
    if (col >= cols) 
        return; 

    const long row = id % rowsC;
    long bBase = col * rowsB;
    long aBase = bBase * rowsC;
    ElemType v = 0;

    if (transposeAColumn)
    {
        aBase += row * rowsB;
        for (long i=0; i<rowsB; i++)
        {
            v += a[aBase++] * b[bBase++];
        }
    }
    else
    {
        aBase += row;
        for (long i=0; i<rowsB; i++)
        {
            v += a[aBase] * b[bBase++];
            aBase += rowsC;
        }
    }
    us[row + col * rowsC] += v;
}

template<class ElemType>
__global__ void _assignElementDivisionOf(
    ElemType* us,
    const ElemType* a,
    const ElemType* b,
    const LONG64 N)
{
    ElemType smallValue = EPS_IN_INVERSE;

    LONG64 id = blockDim.x * blockIdx.x + threadIdx.x;
    if (id>=N)
        return;

    ElemType v = b[id];

    if (v <0 && v > -smallValue)
        us[id] = a[id]/(-smallValue);
    else if (v >=0 && v < smallValue)
        us[id] = a[id]/smallValue;
    else
        us[id]=a[id]/v;
}

template<class ElemType>
__global__ void _elemInverse(
    ElemType* us,
    const LONG64 N)
{
    ElemType smallValue = EPS_IN_INVERSE;

    LONG64 id = blockDim.x * blockIdx.x + threadIdx.x;
    if (id>=N)
        return;

    if (us[id] <0 && us[id] > -smallValue)
        us[id] = 1/-smallValue;
    else if (us[id] >=0 && us[id] < smallValue)
        us[id] = 1/smallValue;
    else
        us[id]=1/us[id];
}

template<class ElemType>
__global__ void _logSoftMaxColWise(
    ElemType *a,
    const long m_numCols,
    const long m_numRows) //ld
{
    int col_id = blockDim.x * blockIdx.x + threadIdx.x;
    if (col_id>=m_numCols)
        return;

    __shared__ ElemType maxV[threadsPerBlock];
    __shared__ ElemType Sum[threadsPerBlock];
    maxV[threadIdx.x]=a[IDX2C(0,col_id,m_numRows)];
    Sum[threadIdx.x]=0;

    for (long i=0;i<m_numRows;++i)
    {
        if (a[IDX2C(i,col_id,m_numRows)]>maxV[threadIdx.x])
        {
            maxV[threadIdx.x]=a[IDX2C(i,col_id,m_numRows)];
        }
    }

    for (long i=0;i<m_numRows;++i)
    {
        ElemType tmp = a[IDX2C(i,col_id,m_numRows)]-maxV[threadIdx.x];
        Sum[threadIdx.x] += (sizeof(ElemType)==sizeof(float) ? expf(tmp) : exp(tmp));
    }
    Sum[threadIdx.x] = maxV[threadIdx.x] + (sizeof(ElemType)==sizeof(float)?logf(Sum[threadIdx.x]):log(Sum[threadIdx.x]));
    for (long i=0;i<m_numRows;++i)
    {
        a[IDX2C(i,col_id,m_numRows)] -= Sum[threadIdx.x] ;
    }
}

//template<class ElemType>
//__global__ void _assignColumnwiseSoftmaxOf(
//    const ElemType *a,
//    ElemType* us,
//    const long m_numCols,
//    const long m_numRows) //thead per column
//{
//    int col_id = blockDim.x * blockIdx.x + threadIdx.x;
//    if (col_id>=m_numCols)
//        return;
//
//    __shared__ ElemType maxV[threadsPerBlock];
//    __shared__ ElemType Sum[threadsPerBlock];
//    maxV[threadIdx.x]=a[IDX2C(0,col_id,m_numRows)];
//    Sum[threadIdx.x]=0;
//
//    for (long i=0;i<m_numRows;++i)
//    {
//        if (a[IDX2C(i,col_id,m_numRows)]>maxV[threadIdx.x])
//        {
//            maxV[threadIdx.x]=a[IDX2C(i,col_id,m_numRows)];
//        }
//    }
//
//    for (long i=0;i<m_numRows;++i)
//    {
//        if (sizeof(ElemType)==sizeof(float))
//        {
//            us[IDX2C(i,col_id,m_numRows)] = expf(a[IDX2C(i,col_id,m_numRows)]-maxV[threadIdx.x]);
//        }
//        else
//        {
//            us[IDX2C(i,col_id,m_numRows)] = exp(a[IDX2C(i,col_id,m_numRows)]-maxV[threadIdx.x]);
//        }
//        Sum[threadIdx.x] +=  us[IDX2C(i,col_id,m_numRows)];
//    }
//
//    for (long i=0;i<m_numRows;++i)
//    {
//        us[IDX2C(i,col_id,m_numRows)] /= Sum[threadIdx.x] ;
//    }
//}

template<class ElemType>
__global__ void _assignColumnwiseLogSoftmaxOf(
    const ElemType *a,
    ElemType* us,
    const long m_numCols,
    const long m_numRows) // each block processes one column. There must be 512 threads in a block
{
    //we first find max per column
    __shared__ ElemType colMax[1];
    __shared__ ElemType partials[512];    
    colMax[0]=-10000000;
    partials[threadIdx.x]=-10000000;

    //int id = blockDim.x * blockIdx.x + threadIdx.x;
    int loadPerThread = m_numRows/blockDim.x; 

    for (int i= threadIdx.x*loadPerThread; i< (threadIdx.x == blockDim.x - 1 ? m_numRows : (threadIdx.x+1)*loadPerThread);++i)
    {
        partials[threadIdx.x]=max(partials[threadIdx.x],a[IDX2C(i,blockIdx.x,m_numRows)]);
    }
    __syncthreads();

    //256
    if (threadIdx.x<256)
    {
        partials[threadIdx.x]=max(partials[threadIdx.x+256],partials[threadIdx.x]);
    }
    __syncthreads();

    //128
    if (threadIdx.x<128)
    {
        partials[threadIdx.x]=max(partials[threadIdx.x+128],partials[threadIdx.x]);
    }
    __syncthreads();

    //64
    if (threadIdx.x<64)
    {
        partials[threadIdx.x]=max(partials[threadIdx.x+64],partials[threadIdx.x]);
    }
    __syncthreads();

    //32
    if (threadIdx.x<32)
    {
        partials[threadIdx.x]=max(partials[threadIdx.x+32],partials[threadIdx.x]);
    }
    __syncthreads();

    //16
    if (threadIdx.x<16)
    {
        partials[threadIdx.x]=max(partials[threadIdx.x+16],partials[threadIdx.x]);
    }
    __syncthreads();

    //8
    if (threadIdx.x<8)
    {
        partials[threadIdx.x]=max(partials[threadIdx.x+8],partials[threadIdx.x]);
    }
    __syncthreads();

    //4
    if (threadIdx.x<4)
    {
        partials[threadIdx.x]=max(partials[threadIdx.x+4],partials[threadIdx.x]);
    }
    __syncthreads();

    if (threadIdx.x==0)
    {
        colMax[0] = max(max(partials[0],partials[1]),max(partials[2],partials[3]));        
    }
    partials[threadIdx.x]=0.0f;
    __syncthreads();
    //end of finding max
    //now start finding sums
    __shared__ ElemType colSum[1];
    colSum[0]=0.0f;
    for (int i= threadIdx.x*loadPerThread; i< (threadIdx.x == blockDim.x - 1 ? m_numRows : (threadIdx.x+1)*loadPerThread);++i)
    {
        ElemType tmp=a[IDX2C(i,blockIdx.x,m_numRows)]-colMax[0];
        us[IDX2C(i,blockIdx.x,m_numRows)]=tmp;
        partials[threadIdx.x]+=(sizeof(ElemType)==sizeof(float)?expf(tmp):exp(tmp));
    }
    __syncthreads();

    //256
    if (threadIdx.x<256)
    {
        partials[threadIdx.x]+=partials[threadIdx.x+256];
    }
    __syncthreads();

    //128
    if (threadIdx.x<128)
    {
        partials[threadIdx.x]+=partials[threadIdx.x+128];
    }
    __syncthreads();

    //64
    if (threadIdx.x<64)
    {
        partials[threadIdx.x]+=partials[threadIdx.x+64];
    }
    __syncthreads();

    //32
    if (threadIdx.x<32)
    {
        partials[threadIdx.x]+=partials[threadIdx.x+32];
    }
    __syncthreads();

    //16
    if (threadIdx.x<16)
    {
        partials[threadIdx.x]+=partials[threadIdx.x+16];
    }
    __syncthreads();

    //8
    if (threadIdx.x<8)
    {
        partials[threadIdx.x]+=partials[threadIdx.x+8];
    }
    __syncthreads();

    //4
    if (threadIdx.x<4)
    {
        partials[threadIdx.x]+=partials[threadIdx.x+4];
    }
    __syncthreads();

    if (threadIdx.x==0)
    {
        colSum[0] = partials[0]+partials[1]+partials[2]+partials[3];
        colSum[0] = (sizeof(ElemType)==sizeof(float)?logf(colSum[0]):log(colSum[0]));
    }
    __syncthreads();
    //end of finding sums
    for (int i= threadIdx.x*loadPerThread; i< (threadIdx.x == blockDim.x - 1 ? m_numRows : (threadIdx.x+1)*loadPerThread);++i)
    {        
        us[IDX2C(i,blockIdx.x,m_numRows)]-=colSum[0];        
    }
}

template<class ElemType>
__global__ void _logSoftMaxRowWise(
    ElemType *a,
    const long m_numCols,
    const long m_numRows) //ld
{
    int row_id = blockDim.x * blockIdx.x + threadIdx.x;
    if (row_id>=m_numRows)
        return;

    __shared__ ElemType maxV[threadsPerBlock];
    __shared__ ElemType Sum[threadsPerBlock];
    maxV[threadIdx.x]=a[IDX2C(row_id,0,m_numRows)];
    Sum[threadIdx.x]=0;

    for (long j=0;j<m_numCols;++j)
    {
        if (a[IDX2C(row_id,j,m_numRows)]>maxV[threadIdx.x])
        {
            maxV[threadIdx.x]=a[IDX2C(row_id,j,m_numRows)];
        }
    }

    for (long j=0;j<m_numCols;++j)
    {
        ElemType tmp = a[IDX2C(row_id,j,m_numRows)]-maxV[threadIdx.x];
        Sum[threadIdx.x] += sizeof(ElemType)==sizeof(float) ? expf(tmp) : exp(tmp);
    }
    Sum[threadIdx.x] = maxV[threadIdx.x]+(sizeof(ElemType)==sizeof(float)?logf(Sum[threadIdx.x]):log(Sum[threadIdx.x]));
    for (long j=0;j<m_numCols;++j)
    {
        a[IDX2C(row_id,j,m_numRows)] -= Sum[threadIdx.x] ;
    }
}

template<class ElemType>
__global__ void _inplaceTruncateBottom(
    ElemType* a,
    const ElemType threshold,
    const LONG64 N)
{
    LONG64 id = blockDim.x * blockIdx.x + threadIdx.x;
    if (id>=N)
        return;
    if (a[id]<threshold)
        a[id]=threshold;
}

template<class ElemType>
__global__ void _assignTruncateBottom(
    ElemType* us,
    const ElemType* a,
    const ElemType threshold,
    const LONG64 N)
{
    LONG64 id = blockDim.x * blockIdx.x + threadIdx.x;
    if (id>=N)
        return;
    if (a[id]<threshold)
        us[id]=threshold;
    else
        us[id]=a[id];
}

template<class ElemType>
__global__ void _inplaceTruncateTop(
    ElemType* a,
    const ElemType threshold,
    const LONG64 N)
{
    LONG64 id = blockDim.x * blockIdx.x + threadIdx.x;
    if (id>=N)
        return;
    if (a[id]>threshold)
        a[id]=threshold;
}

template<class ElemType>
__global__ void _assignTruncateTop(
    ElemType* us,
    const ElemType* a,
    const ElemType threshold,
    const LONG64 N)
{
    LONG64 id = blockDim.x * blockIdx.x + threadIdx.x;
    if (id>=N)
        return;
    if (a[id]>threshold)
        us[id]=threshold;
    else
        us[id]=a[id];
}

template<class ElemType>
__global__ void _setToZeroIfAbsLessThan(
    ElemType* a,
    const ElemType threshold,
    const LONG64 N)
{
    LONG64 id = blockDim.x * blockIdx.x + threadIdx.x;
    if (id>=N)
        return;
    if (sizeof(ElemType)==sizeof(float))
    {
        if (fabsf(a[id])<threshold)
            a[id]=0;
    }
    else
    {
        if (fabs(a[id])<threshold)
            a[id]=0;
    }
}

template<class ElemType>
__global__ void _areEqual(
    const ElemType* a,
    const ElemType* b,
    const LONG64 N,
    const ElemType threshold,
    long *d_res)
{
    LONG64 id = blockDim.x * blockIdx.x + threadIdx.x;
    if (id>=N)
        return;

    if (sizeof(ElemType)==sizeof(float))
    {
        if (fabsf(a[id]-b[id]) > threshold) 
        {
            d_res[0]=0;
        }
    }
    else
    {
        if (fabs(1.0*a[id]-1.0*b[id]) > threshold) 
        {
            d_res[0]=0;
        }
    }

}

template<class ElemType>
__global__ void _setDiagonalValue(
    ElemType* a,
    const ElemType v,
    const unsigned long N,
    const unsigned long ld)
{
    int id = blockDim.x * blockIdx.x + threadIdx.x;
    if (id>=N)
        return;    
    a[IDX2C(id,id,ld)]=v;

}

template<class ElemType>
__global__ void _setDiagonalValueFromVector(
    ElemType* a,
    const ElemType* b,
    const long N)
{
    int id = blockDim.x * blockIdx.x + threadIdx.x;
    if (id>=N)
        return; 
    a[IDX2C(id,id,N)]=b[id];
}

template<class ElemType>
__global__ void _adagrad(
    ElemType* a,
    ElemType* d_v,
    const LONG64 N,
	ElemType* multipliers)
{
    LONG64 id = blockDim.x * blockIdx.x + threadIdx.x;
    if (id >= N)
        return;

    const ElemType floor = 1e-16f;

    a[id] += d_v[id] * d_v[id];
	ElemType temp = sqrt(a[id]+floor);
    d_v[id] /= temp;

	if (multipliers != nullptr)
		multipliers[id] = 1/temp;
}

template<class ElemType>
__global__ void _adagrad4BlockSparse(
    ElemType* a,  //dense
    const size_t numRows, //number of rows in a and in d_v
    ElemType* d_v, //block sparse
    const GPUSPARSE_INDEX_TYPE* blockId2ColOrRow,
    ElemType* multipliers,
    const bool colMajor,
    const size_t len, //major dim, numRows in colMajor and numcols in rowMajor
    const LONG64 N) //total number of non-zero values
{
    LONG64 id = blockDim.x * blockIdx.x + threadIdx.x;
    if (id >= N)
        return;

    const ElemType floor = 1e-16f;
    LONG64 blockid = id / len;  
    LONG64 row = colMajor ? id - blockid*len : blockId2ColOrRow[blockid];
    LONG64 col = colMajor ? blockId2ColOrRow[blockid] : id - blockid*len;

    size_t indexInA = row + col*numRows;
    a[indexInA] += d_v[id] * d_v[id];
    ElemType temp = sqrt(a[indexInA] + floor);
    d_v[id] /= temp;

    if (multipliers != nullptr)
        multipliers[id] = 1 / temp;
}

template<class ElemType>
__global__ void _rmsprop_init(
    ElemType* avars, ElemType* signs, ElemType* steps,
    ElemType* curr_grad,
    const LONG64 N
    )
{
    LONG64 i = blockDim.x * blockIdx.x + threadIdx.x;
    if (i >= N)
        return;

    ElemType tmp = curr_grad[i];
    avars[i] = tmp * tmp;
    signs[i] = ElemType(0.0);
    steps[i] = ElemType(0.02);
}

template<class ElemType>
__global__ void _rmsprop(
    ElemType* avars, ElemType* signs, ElemType* steps,
    ElemType* curr_grad,
    const LONG64 N,
    ElemType RMS_GAMMA,ElemType RMS_WGT_INC,ElemType RMS_WGT_MAX,ElemType RMS_WGT_DEC,ElemType RMS_WGT_MIN,
    ElemType floor,
    ElemType *upd_gpu,
	ElemType* multipliers
    )
{
    LONG64 i = blockDim.x * blockIdx.x + threadIdx.x;
    if (i >= N)
        return;

    avars[i] = RMS_GAMMA * avars[i] + (ElemType(1.0)-RMS_GAMMA)* (curr_grad[i] * curr_grad[i]);

    //// grad sign base 3: 0->neg, 1->zero, 2->pos
    //const int grad_sign = 1 + (ElemType(0) < curr_grad[i]) - (curr_grad[i] < ElemType(0));

    //// signs[i] contains three consecutive grad_sign
    //signs[i]  = 3*(int(signs[i]) % 9) + grad_sign;

    //// update according to the following table:
    //// (!pos,!pos,!pos) or (!neg,!neg,!neg): RMS_WGT_INC
    //// (!neg,!neg,neg) or (!pos,!pos,pos): RMS_WGT_DEC
    //// otherwise: no action

    //switch(int(upd_gpu[int(signs[i])]))
    //{
    //case 0:
    //    steps[i] = max(steps[i] * RMS_WGT_DEC, RMS_WGT_MIN);
    //    break;
    //case 2:
    //    steps[i] = min(steps[i] * RMS_WGT_INC, RMS_WGT_MAX);
    //    break;
    //}
    //curr_grad[i] *= steps[i] / sqrt(avars[i] + floor);

    const int grad_sign = (ElemType(0) < curr_grad[i]) - (curr_grad[i] < ElemType(0));

    if( signs[i] * grad_sign > 0 )
        steps[i] = min(steps[i] * RMS_WGT_INC, RMS_WGT_MAX);
    else
        steps[i] = max(steps[i] * RMS_WGT_DEC, RMS_WGT_MIN);

	ElemType temp = steps[i] / sqrt(avars[i] + floor);
    curr_grad[i] *= temp;
    signs[i] = grad_sign;

	if (multipliers != nullptr)
		multipliers[i] = temp;
}

template<class ElemType>
__global__ void _rescaleToRange(
    ElemType* a,
    const LONG64 N,
    const ElemType low,
    const ElemType high)
{
    LONG64 id = blockDim.x * blockIdx.x + threadIdx.x;
    if (id>=N)
        return;    
    a[id]=a[id]*(high-low)+low;
}

template<class ElemType>
__global__ void _setMaskAndScale(
    ElemType* a,
    const LONG64 N,
    const ElemType maskRate,
    const ElemType scaleValue)
{
    LONG64 id = blockDim.x * blockIdx.x + threadIdx.x;
    if (id>=N)
        return;    
    a[id]=a[id]<=maskRate? 0 : scaleValue;
}

template<class ElemType>
__global__ void _vectorSum(
    ElemType* c, //output
    const ElemType* a, //input
    const long n, //a.numRows
    const long m, //a.numCols
    const bool isColWise)
{
    int id = blockDim.x * blockIdx.x + threadIdx.x;
    if ((isColWise && id >= m) || (!isColWise && id >= n))
        return;

    ElemType sum = 0;

    if (isColWise)
    {
        for (long i = 0; i<n; ++i)
        {
            sum += a[IDX2C(i, id, n)];
        }
    }
    else
    {
        for (long j = 0; j<m; ++j)
        {
            sum += a[IDX2C(id, j, n)];
        }
    }
    c[id] = sum;
}

template<class ElemType>
__global__ void _vectorNorm1(
    ElemType* c, //output
    const ElemType* a, //input
    const long n, //a.numRows
    const long m, //a.numCols
    const bool isColWise)
{
    int id = blockDim.x * blockIdx.x + threadIdx.x;
    if ((isColWise && id>=m)||(!isColWise && id>=n))
        return;

    ElemType sum = 0;

    if (isColWise)
    {
        for (long i=0;i<n;++i)
        {
            if (sizeof(ElemType)==sizeof(float))
            {
                sum+=fabsf(a[IDX2C(i,id,n)]);
            }
            else
            {
                sum+=fabs(a[IDX2C(i,id,n)]);
            }
        }
    }
    else
    {
        for (long j=0;j<m;++j)
        {
            if (sizeof(ElemType)==sizeof(float))
            {
                sum+=fabsf(a[IDX2C(id,j,n)]);
            }
            else
            {
                sum+=fabs(a[IDX2C(id,j,n)]);
            }
        }
    }
    c[id]=sum;
}


//one column per thread
template<class ElemType>
__global__ void _vectorNorm2(
    ElemType* c,  //output
    const ElemType* a, //input
    const long N, //a.GetNumRows();
    const long M, //a.GetNumCols();
    const bool isColWise) 
{
    long id = blockDim.x * blockIdx.x + threadIdx.x;
    if ((isColWise && id>=M) || (!isColWise && id>=N))
        return;

    ElemType sum = 0;
    if (isColWise)
    {
        for (long i=0;i<N;++i)
        {
            ElemType v = a[IDX2C(i,id,N)];
            sum += v * v;
        }
    }
    else
    {
        for (long j=0;j<M;++j)
        {
            ElemType v = a[IDX2C(id,j,N)];
            sum += v * v;
        }
    }

    if (sizeof(ElemType) == sizeof(float))
        c[id] = sqrtf(sum);
    else
        c[id] = sqrt(sum);
}

template<class ElemType>
__global__ void _convertInd2ValsAdjustInd(
    ElemType* inds,
    const ElemType* M,
    ElemType* vals,    
    const long n, //number of cols
    const long m, //number of rows
    const bool isColWise)
{
    int id = blockDim.x * blockIdx.x + threadIdx.x;
    if ((isColWise && id>=n)||(!isColWise && id>=m))
        return;
    inds[id]--;
    if (isColWise)
    {
        vals[id]=M[IDX2C((int)inds[id],id,m)];
    }
    else
    {
        vals[id]=M[IDX2C(id,(int)inds[id],m)];
    }
}


    //assume each column is an input sample. Each sample is stored in [channel, row, col]  (r00, g00, b00, r01, g01, b01, r10, g10, b10, r11, g11, b11)
template<class ElemType>
__global__ void _assignPackedConvolutionInput(ElemType * packedMatrix, const ElemType * inputSubBatch, const long batchSize,
                                                 const long inputWidth, const long inputHeight, const long inputChannels,
                                                 const long outputWidth, const long outputHeight, const long outputChannels,
                                                 const long kernelWidth, const long kernelHeight, const long horizontalSubsample, const long verticalSubsample, const bool zeroPadding)
{
    const long inputHeightTimesChannel = inputHeight * inputChannels; 
    const size_t inputDim = inputWidth*inputHeightTimesChannel;

    const long idall = blockIdx.x * blockDim.x + threadIdx.x; 
    const long sample = idall / inputDim;
    if (sample >= batchSize) 
        return; 

    const long id = idall % inputDim;
    const long y = id / inputHeightTimesChannel; //inputCol

    const size_t packedInputRows = kernelWidth * kernelHeight * inputChannels;
    const size_t packedInputColsPerSample = outputWidth * outputHeight;  //output size per channel

    // IN_ELEM_ROWPOS(channel, row, col) = (channel + (row + col * inputHeight) * inputChannels)
    // IN_ELEM_COLPOS = sample

    const long nXC = id % inputHeightTimesChannel; //channel + inputRow*inputChannels
    const long x = nXC / inputChannels; //inputRow
    const long c = nXC % inputChannels; //channel

    ElemType currentInputValue = inputSubBatch[id + sample*inputDim]; 

    long x0 = 0, y0 = 0, x1 = 0, y1 = 0;
    if (zeroPadding)
    {
        const long halfKernelWidth = kernelWidth/2; 
        const long halfKernelHeight = kernelHeight/2; 

        x0 = max(0.0f, ceil((x-(ElemType)kernelHeight+1.0f+halfKernelHeight)/ (ElemType)verticalSubsample));  //row : first wrow in which x is in
        x1 = x+halfKernelHeight-x0*verticalSubsample;    //first posxInKernel
        y0 = max(0.0f, ceil((y-(ElemType)kernelWidth+1.0f+halfKernelWidth)/(ElemType)horizontalSubsample));  //col : first wcol in which y is in
        y1 = y+halfKernelWidth-y0*horizontalSubsample;  //first posyInKernel
    }
    else
    {
        x0 = max(0.0f, ceil((x-(ElemType)kernelHeight+1)/ (ElemType)verticalSubsample));  //row : first wrow in which x is in
        x1 = x-x0*verticalSubsample;    //first posxInKernel
        y0 = max(0.0f, ceil((y-(ElemType)kernelWidth+1)/(ElemType)horizontalSubsample));  //col : first wcol in which y is in
        y1 = y-y0*horizontalSubsample;  //first posyInKernel
    }

    // PACK_ELEM_ROWPOS(channel, posxInKernel, posyInKernel) = (channel * kernelWidth * kernelHeight + posxInKernel + posyInKernel * kernelHeight)
    // PACK_ELEM_COLPOS(sample, wrow, wcol) = (sample*packedInputColsPerSample + outputHeight*wcol + wrow

    long packColBase = sample*packedInputColsPerSample + y0*outputHeight; 
    for (long wcol = y0, posyInKernel = y1; wcol < outputWidth && posyInKernel>=0; wcol++, posyInKernel -= horizontalSubsample) 
    {
        long packRowBase = c * kernelWidth * kernelHeight + posyInKernel * kernelHeight;
        for (long wrow = x0, posxInKernel = x1; wrow < outputHeight && posxInKernel>=0; wrow++, posxInKernel -= verticalSubsample) 
        {
            const long packRow = packRowBase + posxInKernel; 
            const long packCol = packColBase + wrow; 
            packedMatrix[packRow + packCol*packedInputRows] = currentInputValue; 
        }
        packColBase += outputHeight; 
    }
}

    //assume each column is an input sample. Each sample is stored in [channel, row, col]  (r00, g00, b00, r01, g01, b01, r10, g10, b10, r11, g11, b11)
template<class ElemType>
__global__ void _unpackConvolutionInput(const ElemType * packedMatrix, ElemType * inputSubBatch, const long batchSize,
                                                 const long inputWidth, const long inputHeight, const long inputChannels,
                                                 const long outputWidth, const long outputHeight, const long outputChannels,
                                                 const long kernelWidth, const long kernelHeight, const long horizontalSubsample, const long verticalSubsample, const bool zeroPadding)
{
    const long inputHeightTimesChannel = inputHeight * inputChannels; 
    const size_t inputDim = inputWidth*inputHeightTimesChannel;

    const long idall = blockIdx.x * blockDim.x + threadIdx.x; 
    const long sample = idall / inputDim;
    if (sample >= batchSize) 
        return; 

    const long id = idall % inputDim;
    const long y = id / inputHeightTimesChannel; //inputCol

    const size_t packedInputRows = kernelWidth * kernelHeight * inputChannels;
    const size_t packedInputColsPerSample = outputWidth * outputHeight;  //output size per channel

    // IN_ELEM_ROWPOS(channel, row, col) = (channel + (row + col * inputHeight) * inputChannels)
    // IN_ELEM_COLPOS = sample

    const long nXC = id % inputHeightTimesChannel; //channel + inputRow*inputChannels
    const long x = nXC / inputChannels; //inputRow
    const long c = nXC % inputChannels; //channel

    long x0 = 0, y0 = 0, x1 = 0, y1 = 0;
    if (zeroPadding)
    {
        const long halfKernelWidth = kernelWidth/2; 
        const long halfKernelHeight = kernelHeight/2; 

        x0 = max(0.0f, ceil((x-(ElemType)kernelHeight+1.0f+halfKernelHeight)/ (ElemType)verticalSubsample));  //row : first wrow in which x is in
        x1 = x+halfKernelHeight-x0*verticalSubsample;    //first posxInKernel
        y0 = max(0.0f, ceil((y-(ElemType)kernelWidth+1.0f+halfKernelWidth)/(ElemType)horizontalSubsample));  //col : first wcol in which y is in
        y1 = y+halfKernelWidth-y0*horizontalSubsample;  //first posyInKernel
    }
    else
    {
        x0 = max(0.0f, ceil((x-(ElemType)kernelHeight+1)/ (ElemType)verticalSubsample));  //row : first wrow in which x is in
        x1 = x-x0*verticalSubsample;    //first posxInKernel
        y0 = max(0.0f, ceil((y-(ElemType)kernelWidth+1)/(ElemType)horizontalSubsample));  //col : first wcol in which y is in
        y1 = y-y0*horizontalSubsample;  //first posyInKernel
    }

    // PACK_ELEM_ROWPOS(channel, posxInKernel, posyInKernel) = (channel * kernelWidth * kernelHeight + posxInKernel + posyInKernel * kernelHeight)
    // PACK_ELEM_COLPOS(sample, wrow, wcol) = (sample*packedInputColsPerSample + outputHeight*wcol + wrow

    ElemType currentInputValue = inputSubBatch[id + sample*inputDim]; 
    long packColBase = sample*packedInputColsPerSample + y0*outputHeight; 
    for (long wcol = y0, posyInKernel = y1; wcol < outputWidth && posyInKernel>=0; wcol++, posyInKernel -= horizontalSubsample) 
    {
        long packRowBase = c * kernelWidth * kernelHeight + posyInKernel * kernelHeight;
        for (long wrow = x0, posxInKernel = x1; wrow < outputHeight && posxInKernel>=0; wrow++, posxInKernel -= verticalSubsample) 
        {
            const long packRow = packRowBase + posxInKernel; 
            const long packCol = packColBase + wrow; 
            currentInputValue += packedMatrix[packRow + packCol*packedInputRows]; 
        }
        packColBase += outputHeight; 
    }

    inputSubBatch[id + sample*inputDim] = currentInputValue; 
}

template<class ElemType>
__global__ void _assignMaxPoolingResult(ElemType * outputBatch, const ElemType * inputBatch, const long batchSize, const long channels,
                                                const long inputWidth, const long inputHeight,  const long inputSizePerSample, 
                                                const long outputWidth, const long outputHeight, const long outputSizePerSample, 
                                                const long windowWidth, const long windowHeight, const long horizontalSubsample, const long verticalSubsample)
{
    const long outputIndex = blockIdx.x * blockDim.x + threadIdx.x; 
    const long sample = outputIndex / outputSizePerSample; 
    if (sample >= batchSize) 
        return; 

    const long outputIndexWithinSample = outputIndex % outputSizePerSample; 
    const long inputHeightTimesChannel = inputHeight * channels; 
    const long outputHeightTimesChannel = outputHeight * channels; 


    // IN_ELEM_ROWPOS(channel, row, col) = (channel + (row + col * inputHeight) * channels)
    // IN_ELEM_COLPOS = sample

    // OUT_ELEM_ROWPOS(channel, wrow, wcol) = (channel + (wrow + wcol * outputHeight) * channels)
    // OUT_ELEM_COLPOS = sample

    const long y = outputIndexWithinSample / outputHeightTimesChannel; //wcol
    const long nXC = outputIndexWithinSample % outputHeightTimesChannel; //channel + wrow*channels
    const long x = nXC / channels; //wrow
    const long c = nXC % channels; //channel

    const ElemType *inputBatchBase4Sample = inputBatch + sample*inputSizePerSample;
    register ElemType maxVal = -FLT_MAX; 
    const long rowInWindowBase = (x*verticalSubsample + y*horizontalSubsample*inputHeight)*channels+c;
    for (long colInWindow=0; colInWindow<windowWidth; colInWindow++) 
    {   
        long rowInInput = rowInWindowBase + colInWindow * inputHeightTimesChannel;
        for (long rowInWindow=0; rowInWindow<windowHeight; rowInWindow++)
        {
            const ElemType val = inputBatchBase4Sample[rowInInput]; 
            maxVal = max(maxVal, val); 
            rowInInput += channels;
        }
    }
    outputBatch[outputIndexWithinSample + sample*outputSizePerSample] = maxVal; 
}

template<class ElemType>
__global__ void _addMaxPoolingGradient(ElemType * inputGradientBatch, const ElemType * outputGradientBatch, const ElemType * inputBatch, const ElemType * outputBatch, 
                                                const long batchSize, const long channels, 
                                                const long inputWidth, const long inputHeight, const long inputSizePerSample, 
                                                const long outputWidth, const long outputHeight, const long outputSizePerSample, 
                                                const long windowWidth, const long windowHeight, const long horizontalSubsample, const long verticalSubsample)
{
    const long inputIndex = blockIdx.x * blockDim.x + threadIdx.x; 
    const long sample = inputIndex / inputSizePerSample; 
    if (sample >= batchSize) 
        return; 
   
    const long inputIndexWithinSample = inputIndex % inputSizePerSample; 

    const long inputHeightTimesChannel = inputHeight * channels; 
    const long outputHeightTimesChannel = outputHeight * channels; 

    // IN_ELEM_ROWPOS(channel, row, col) = (channel + (row + col * inputHeight) * channels)
    // IN_ELEM_COLPOS = sample

    // OUT_ELEM_ROWPOS(channel, wrow, wcol) = (channel + (wrow + wcol * outputHeight) * channels)
    // OUT_ELEM_COLPOS = sample

    const long y = inputIndexWithinSample / inputHeightTimesChannel; //col in input
    const long nXC = inputIndexWithinSample % inputHeightTimesChannel; //channel + row*chanels
    const long x = nXC / channels; //row in input
    const long c = nXC % channels; //channel

    long startOutX = max(0.0f, ceil((x-(ElemType)windowHeight+1)/ (ElemType)verticalSubsample));  //inclusive start
    long endOutX = (x/verticalSubsample < outputHeight-1)? x/verticalSubsample : outputHeight-1; //inclusive end
    long startOutY = max(0.0f, ceil((y-(ElemType)windowWidth+1)/(ElemType)horizontalSubsample));  //inclusive start
    long endOutY = (x/horizontalSubsample < outputWidth-1)? x/horizontalSubsample : outputWidth-1; //inclusive end


    ElemType *inputGradientBatchBase4Sample = inputGradientBatch + sample*inputSizePerSample;
    const ElemType *outputGradientBatchBase4Sample = outputGradientBatch + sample*outputSizePerSample;
    const ElemType * outputBatchBase4Sample = outputBatch + sample*outputSizePerSample;

    ElemType inputValue = inputBatch[inputIndexWithinSample + sample*inputSizePerSample];
    for (long outY=startOutY; outY<=endOutY; outY++)
    {
        for (long outX=startOutX; outX<=endOutX; outX++)
        {
            long outputIndex = outY * outputHeightTimesChannel + outX * channels + c; 
            if (inputValue == outputBatchBase4Sample[outputIndex])
                inputGradientBatchBase4Sample[inputIndexWithinSample] += outputGradientBatchBase4Sample[outputIndex];
        }
    }  
}
template<class ElemType>
__global__ void _assignAveragePoolingResult(ElemType * outputBatch, const ElemType * inputBatch, const long batchSize, const long channels,
                                                const long inputWidth, const long inputHeight,  const long inputSizePerSample, 
                                                const long outputWidth, const long outputHeight, const long outputSizePerSample, 
                                                const long windowWidth, const long windowHeight, const long horizontalSubsample, const long verticalSubsample)
{
    const long outputIndex = blockIdx.x * blockDim.x + threadIdx.x; 
    const long sample = outputIndex / outputSizePerSample; 
    if (sample >= batchSize) 
        return; 

    const long outputIndexWithinSample = outputIndex % outputSizePerSample; 
    const long inputHeightTimesChannel = inputHeight * channels; 
    const long outputHeightTimesChannel = outputHeight * channels; 


    // IN_ELEM_ROWPOS(channel, row, col) = (channel + (row + col * inputHeight) * channels)
    // IN_ELEM_COLPOS = sample

    // OUT_ELEM_ROWPOS(channel, wrow, wcol) = (channel + (wrow + wcol * outputHeight) * channels)
    // OUT_ELEM_COLPOS = sample

    const long y = outputIndexWithinSample / outputHeightTimesChannel; //wcol
    const long nXC = outputIndexWithinSample % outputHeightTimesChannel; //channel + wrow*channels
    const long x = nXC / channels; //wrow
    const long c = nXC % channels; //channel

    const ElemType *inputBatchBase4Sample = inputBatch + sample*inputSizePerSample;

    register ElemType average = 0; 
    const long rowInWindowBase = (x*verticalSubsample + y*horizontalSubsample*inputHeight)*channels+c;
    for (long colInWindow=0; colInWindow<windowWidth; colInWindow++) 
    {   
        long rowInInput = rowInWindowBase + colInWindow * inputHeightTimesChannel;
        for (long rowInWindow=0; rowInWindow<windowHeight; rowInWindow++)
        {
            average += inputBatchBase4Sample[rowInInput]; 
            rowInInput += channels;
        }
    }

    outputBatch[outputIndexWithinSample + sample*outputSizePerSample] = average/windowWidth/windowHeight; 
}

template<class ElemType>
__global__ void _addAveragePoolingGradient(ElemType * inputGradientBatch, const ElemType * outputGradientBatch, 
                                                const long batchSize, const long channels, 
                                                const long inputWidth, const long inputHeight, const long inputSizePerSample, 
                                                const long outputWidth, const long outputHeight, const long outputSizePerSample, 
                                                const long windowWidth, const long windowHeight, const long horizontalSubsample, const long verticalSubsample)
{
    const long inputIndex = blockIdx.x * blockDim.x + threadIdx.x; 
    const long sample = inputIndex / inputSizePerSample; 
    if (sample >= batchSize) 
        return; 
   
    const long inputIndexWithinSample = inputIndex % inputSizePerSample; 

    const long inputHeightTimesChannel = inputHeight * channels; 
    const long outputHeightTimesChannel = outputHeight * channels; 
    const long windowSize = windowWidth * windowHeight;

    // IN_ELEM_ROWPOS(channel, row, col) = (channel + (row + col * inputHeight) * channels)
    // IN_ELEM_COLPOS = sample

    // OUT_ELEM_ROWPOS(channel, wrow, wcol) = (channel + (wrow + wcol * outputHeight) * channels)
    // OUT_ELEM_COLPOS = sample

    const long y = inputIndexWithinSample / inputHeightTimesChannel; //col in input
    const long nXC = inputIndexWithinSample % inputHeightTimesChannel; //channel + row*chanels
    const long x = nXC / channels; //row in input
    const long c = nXC % channels; //channel

    long startOutX = max(0.0f, ceil((x-(ElemType)windowHeight+1)/ (ElemType)verticalSubsample));  //inclusive start
    long endOutX = (x/verticalSubsample < outputHeight-1)? x/verticalSubsample : outputHeight-1; //inclusive end
    long startOutY = max(0.0f, ceil((y-(ElemType)windowWidth+1)/(ElemType)horizontalSubsample));  //inclusive start
    long endOutY = (x/horizontalSubsample < outputWidth-1)? x/horizontalSubsample : outputWidth-1; //inclusive end

    ElemType *inputGradientBatchBase4Sample = inputGradientBatch + sample*inputSizePerSample;
    const ElemType *outputGradientBatchBase4Sample = outputGradientBatch + sample*outputSizePerSample;

    for (long outY=startOutY; outY<=endOutY; outY++)
    {
        for (long outX=startOutX; outX<=endOutX; outX++)
        {
            long outputIndex = outY * outputHeightTimesChannel + outX * channels + c; 
            inputGradientBatchBase4Sample[inputIndexWithinSample] += outputGradientBatchBase4Sample[outputIndex]/windowSize;
        }
    }  
}

template<class ElemType>
__global__ void _addMaxPoolingGradientLoopOut(ElemType * inputGradientBatch, const ElemType * outputGradientBatch, const ElemType * inputBatch, const ElemType * outputBatch, 
                                                const long batchSize, const long channels, 
                                                const long inputWidth, const long inputHeight, const long inputSizePerSample, 
                                                const long outputWidth, const long outputHeight, const long outputSizePerSample, 
                                                const long windowWidth, const long windowHeight, const long horizontalSubsample, const long verticalSubsample)
{
    const long outputIndex = blockIdx.x * blockDim.x + threadIdx.x; 
    const long sample = outputIndex / outputSizePerSample; 
    if (sample >= batchSize) 
        return; 
   
    const long outputIndexWithinSample = outputIndex % outputSizePerSample; 
    const long inputWidthTimesChannel = inputWidth * channels; 
    const long outputWidthTimesChannel = outputWidth * channels; 
    const long y = outputIndexWithinSample / outputWidthTimesChannel; 
    const long nXC = outputIndexWithinSample % outputWidthTimesChannel; 
    const long x = nXC / channels; 
    const long c = nXC % channels; 

    const long offset0 = sample*inputSizePerSample + y*verticalSubsample*inputWidthTimesChannel + x*horizontalSubsample*channels;
    const ElemType *pCurWindow4Input = inputBatch + offset0; // pooling to current window's first input pixel 
    ElemType *pCurWindow4InGradient = inputGradientBatch + offset0; 
    for (long yy=0; yy<windowHeight; yy++) 
    {
        const long offset1 = yy*inputWidthTimesChannel + c; 
        const ElemType *pf0 = pCurWindow4Input + offset1; 
        ElemType *pf1 = pCurWindow4InGradient + offset1; 
        for (long xx=0; xx<windowWidth; xx++)
        {
            const long offset2 = xx*channels; 
            if (pf0[offset2] == outputBatch[outputIndex]) 
            {
                pf1[offset2] += outputGradientBatch[outputIndex]; //need to be atomic however atomicAdd on double is not supported.
            }
        }
    }
}

template<class ElemType>
__global__ void _addElementProductOf(
    ElemType* us,
    const ElemType* a,
    const ElemType* b,
    const LONG64 N)
{
    LONG64 id = blockDim.x * blockIdx.x + threadIdx.x;
    if (id>=N)
        return;
    us[id]+=(a[id]*b[id]);
}

template<class ElemType>
__global__ void _columnElementMultiplyWith(
    ElemType* us,
    const ElemType* a,
    const long N, //a.GetNumRows();
    const long M) //us.GetNumCols();
{
    long id = blockDim.x * blockIdx.x + threadIdx.x;
    if (id>=N)
        return;

    //__shared__ ElemType _a[threadsPerBlock];
    //_a[threadIdx.x]=a[id];
    ElemType mul=a[id];
    for (long j=0;j<M;++j)
    {
        us[IDX2C(id,j,N)]=us[IDX2C(id,j,N)]*mul;
    }
}

template<class ElemType>
__global__ void _rowElementMultiplyWith(
    ElemType* us,
    const ElemType* a,
    const long N, //us.GetNumRows();
    const long M) //a.GetNumCols();
{
    long id = blockDim.x * blockIdx.x + threadIdx.x;
    if (id>=M)
        return;

    //__shared__ ElemType _a[threadsPerBlock];
    //_a[threadIdx.x]=a[id];
    ElemType mul=a[id];
    for (long i=0;i<N;++i)
    {
        us[IDX2C(i,id,N)]=us[IDX2C(i,id,N)]*mul;
    }
}

template<class ElemType>
__global__ void _rowElementDivideBy(
    ElemType* us,
    const ElemType* a,
    const long N, //us.GetNumRows();
    const long M) //a.GetNumCols();
{
    long id = blockDim.x * blockIdx.x + threadIdx.x;
    if (id >= M)
        return;

    //__shared__ ElemType _a[threadsPerBlock];
    //_a[threadIdx.x]=a[id];
    ElemType v = a[id];
    if (v >= 0 && v < EPS_IN_INVERSE)
        v = EPS_IN_INVERSE;
    else if (v < 0 && v > -EPS_IN_INVERSE)
        v = (-EPS_IN_INVERSE);

    for (long i = 0; i<N; ++i)
    {
        us[IDX2C(i, id, N)] = us[IDX2C(i, id, N)] / v;
    }
}

template<class ElemType>
__global__ void _ColumnElementDivideBy(
    ElemType* us,
    const ElemType* a,
    const long N, //a.GetNumRows();
    const long M) //us.GetNumCols();
{
    long id = blockDim.x * blockIdx.x + threadIdx.x;
    if (id>=N)
        return;

    ElemType smallValue = EPS_IN_INVERSE;

    //__shared__ ElemType _a[threadsPerBlock];
    //_a[threadIdx.x]=a[id];
    ElemType v=a[id];
    for (long j=0;j<M;++j)
    {
        if (v <0 && v > -smallValue)
            us[IDX2C(id,j,N)] /= (-smallValue);
        else if (v >=0 && v < smallValue)
            us[IDX2C(id,j,N)] /= smallValue;
        else
            us[IDX2C(id,j,N)] /= v;
    }

}


template<class ElemType>
__global__ void _innerProduct(
    ElemType* c,
    const ElemType* a,
    const ElemType* b,
    const long N, //a.GetNumRows();
    const long M, //a.GetNumCols();
    const bool isColWise) 
{
    long id = blockDim.x * blockIdx.x + threadIdx.x;
    if ((isColWise && id>=M) || (!isColWise && id>=N))
        return;

    ElemType sum = 0;
    long index;
    if (isColWise)
    {
        for (long i=0; i<N; ++i)
        {
            index = IDX2C(i,id,N);
            sum += a[index]* b[index];
        }
    }
    else
    {
        for (long j=0; j<M; ++j)
        {
            index = IDX2C(id,j, N);
            sum += a[index]* b[index];
        }
    }

    c[id] = sum;
}


template<class ElemType>
__global__ void _assignSignOf(
    ElemType* a,
    const ElemType* b,
    const LONG64 N)
{
    LONG64 id = blockDim.x * blockIdx.x + threadIdx.x;
    if (id>=N)
        return;
    ElemType v = b[id];
    a[id] = (v == (ElemType)0? (ElemType)0 : (v > 0? (ElemType)1 : (ElemType)(-1)));
}

template<class ElemType>
__global__ void _addSignOf(
    ElemType* a,
    const ElemType* b,
    const LONG64 N)
{
    LONG64 id = blockDim.x * blockIdx.x + threadIdx.x;
    if (id>=N)
        return;
    ElemType v = b[id];
    a[id] += (v == (ElemType)0? (ElemType)0 : (v > 0? (ElemType)1 : (ElemType)(-1)));
}

template<class ElemType>
__global__ void _vectorMaxMinReduce( //this function processes 1 column per block. this function needs 512 threads
                                 const ElemType* us,
                                 ElemType* Indexes,
                                 ElemType* Values,
                                 const long m,  //number of rows
                                 const long n,
                                 bool isMax)  //number of cols
{
    //we first find max per column    
    __shared__ ElemType partials[512];        
    __shared__ int partialsInd[512];
    if (isMax)
    {
        partials[threadIdx.x]=-10000000;
    }
    else
    {
        partials[threadIdx.x]=10000000;
    }
    partialsInd[threadIdx.x]=-1;

    //int id = blockDim.x * blockIdx.x + threadIdx.x;
    int loadPerThread = m/blockDim.x; 

    for (int i= threadIdx.x*loadPerThread; i< (threadIdx.x == blockDim.x - 1 ? m : (threadIdx.x+1)*loadPerThread);++i)
    {
        if (( isMax ? us[IDX2C(i,blockIdx.x,m)]>partials[threadIdx.x] : us[IDX2C(i,blockIdx.x,m)]<partials[threadIdx.x]) || partialsInd[threadIdx.x]==-1)
        {
            partials[threadIdx.x]=us[IDX2C(i,blockIdx.x,m)];
            partialsInd[threadIdx.x]=i;       
        }
    }
    __syncthreads();

    //256
    if (threadIdx.x<256)
    {
        //partials[threadIdx.x]=max(partials[threadIdx.x+256],partials[threadIdx.x]);
        if ((isMax ? partials[threadIdx.x+256]>partials[threadIdx.x] : partials[threadIdx.x+256]<partials[threadIdx.x]) || partialsInd[threadIdx.x]==-1)
        {
            partials[threadIdx.x]=partials[threadIdx.x+256];
            partialsInd[threadIdx.x]=partialsInd[threadIdx.x+256];
        }
    }
    __syncthreads();

    //128
    if (threadIdx.x<128)
    {
        //partials[threadIdx.x]=max(partials[threadIdx.x+128],partials[threadIdx.x]);
        if ((isMax ? partials[threadIdx.x+128]>partials[threadIdx.x] : partials[threadIdx.x+128]<partials[threadIdx.x]) || partialsInd[threadIdx.x]==-1)
        {
            partials[threadIdx.x]=partials[threadIdx.x+128];
            partialsInd[threadIdx.x]=partialsInd[threadIdx.x+128];
        }
    }
    __syncthreads();

    //64
    if (threadIdx.x<64)
    {
        //partials[threadIdx.x]=max(partials[threadIdx.x+64],partials[threadIdx.x]);
        if ((isMax ? partials[threadIdx.x+64]>partials[threadIdx.x] : partials[threadIdx.x+64]<partials[threadIdx.x]) || partialsInd[threadIdx.x]==-1)
        {
            partials[threadIdx.x]=partials[threadIdx.x+64];
            partialsInd[threadIdx.x]=partialsInd[threadIdx.x+64];
        }
    }
    __syncthreads();

    //32
    if (threadIdx.x<32)
    {
        //partials[threadIdx.x]=max(partials[threadIdx.x+32],partials[threadIdx.x]);
        if ((isMax ? partials[threadIdx.x+32]>partials[threadIdx.x] : partials[threadIdx.x+32]<partials[threadIdx.x]) || partialsInd[threadIdx.x]==-1)
        {
            partials[threadIdx.x]=partials[threadIdx.x+32];
            partialsInd[threadIdx.x]=partialsInd[threadIdx.x+32];
        }
    }
    __syncthreads();

    //16
    if (threadIdx.x<16)
    {
        //partials[threadIdx.x]=max(partials[threadIdx.x+16],partials[threadIdx.x]);
        if ((isMax ? partials[threadIdx.x+16]>partials[threadIdx.x] : partials[threadIdx.x+16]<partials[threadIdx.x]) || partialsInd[threadIdx.x]==-1)
        {
            partials[threadIdx.x]=partials[threadIdx.x+16];
            partialsInd[threadIdx.x]=partialsInd[threadIdx.x+16];
        }
    }
    __syncthreads();

    //8
    if (threadIdx.x<8)
    {
        //partials[threadIdx.x]=max(partials[threadIdx.x+8],partials[threadIdx.x]);
        if ((isMax ? partials[threadIdx.x+8]>partials[threadIdx.x] : partials[threadIdx.x+8]<partials[threadIdx.x]) || partialsInd[threadIdx.x]==-1)
        {
            partials[threadIdx.x]=partials[threadIdx.x+8];
            partialsInd[threadIdx.x]=partialsInd[threadIdx.x+8];
        }
    }
    __syncthreads();

    //4
    if (threadIdx.x<4)
    {
        //partials[threadIdx.x]=max(partials[threadIdx.x+4],partials[threadIdx.x]);
        if ((isMax ? partials[threadIdx.x+4]>partials[threadIdx.x] : partials[threadIdx.x+4]<partials[threadIdx.x]) || partialsInd[threadIdx.x]==-1)
        {
            partials[threadIdx.x]=partials[threadIdx.x+4];
            partialsInd[threadIdx.x]=partialsInd[threadIdx.x+4];
        }
    }
    __syncthreads();

    if (threadIdx.x==0)
    {
        ElemType mx = partials[0];
        int ind = partialsInd[0];
        if ((isMax ? mx<partials[1] : mx>partials[1]) || ind ==-1)
        {
            mx = partials[1];
            ind = partialsInd[1];
        }
        if ((isMax ? mx<partials[2] : mx>partials[2]) || ind ==-1)
        {
            mx = partials[2];
            ind = partialsInd[2];
        }
        if ((isMax ? mx<partials[3] : mx>partials[3]) || ind ==-1)
        {
            mx = partials[3];
            ind = partialsInd[3];
        }
        Values[blockIdx.x] = mx;
        Indexes[blockIdx.x] = ind;
    }
}

template<class ElemType>
__global__ void _vectorMax(
    const ElemType* us,
    ElemType* maxIndexes,
    ElemType* maxValues,
    const long m,  //number of rows
    const long n,  //number of cols
    const bool isColWise) 
{
    long id = blockDim.x * blockIdx.x + threadIdx.x;
    long maxInd = -1;
    ElemType maxVal = -100000;

    if (isColWise)
    {
        if (id>=n)
            return;

        for (long i=0;i<m;i++)
        {
            if (maxInd==-1 || us[IDX2C(i,id,m)]>=maxVal)
            {
                maxInd = i;
                maxVal = us[IDX2C(i,id,m)];
            }
        }
    }
    else
    {
        if (id>=m)
            return;

        for (long j=0;j<n;j++)
        {
            if (maxInd==-1 || us[IDX2C(id,j,m)]>=maxVal)
            {
                maxInd = j;
                maxVal = us[IDX2C(id,j,m)];
            }
        }
    }
    maxIndexes[id]=maxInd;
    maxValues[id]=maxVal;
}

template<class ElemType>
__global__ void _vectorMin(
    const ElemType* us,
    ElemType* minIndexes,
    ElemType* minValues,
    const long m,  //number of rows
    const long n,  //number of cols
    const bool isColWise) 
{
    long id = blockDim.x * blockIdx.x + threadIdx.x;
    long minInd = -1;
    ElemType minVal = -100000;

    if (isColWise)
    {
        if (id>=n)
            return;

        for (long i=0;i<m;i++)
        {
            if (minInd==-1 || us[IDX2C(i,id,m)]<=minVal)
            {
                minInd = i;
                minVal = us[IDX2C(i,id,m)];
            }
        }
    }
    else
    {
        if (id>=m)
            return;

        for (long j=0;j<n;j++)
        {
            if (minInd==-1 || us[IDX2C(id,j,m)]<=minVal)
            {
                minInd = j;
                minVal = us[IDX2C(id,j,m)];
            }
        }
    }
    minIndexes[id]=minInd;
    minValues[id]=minVal;
}

//this implementation uses more threads but also more memory access
template<class ElemType>
__global__ void _matrixVectorColumnWiseAddWithThreadPerElem(
    const ElemType* a,
    ElemType* us,
    ElemType alpha,
    const long m,  //number of rows
    const long n)  //number of cols     
{
    long id = blockDim.x * blockIdx.x + threadIdx.x;
    if (id >= m*n)
        return;

    long col = id / m;
    long row = id - col*m;

    us[id] += alpha*a[row];
}

template<class ElemType>
__global__ void _matrixVectorColumnWiseAddWithThreadPerRow(
    const ElemType* a,
    ElemType* us,
    ElemType alpha,
    const long m,  //number of rows
    const long n)  //number of cols     
{
#ifdef VALIDATION
    if (blockDim.x * blockIdx.x + threadIdx.x == 0)
    {
        printf("** _matrixVectorColumnWiseAdd on device:\na = %p, us = %p, alpha = %f, m = %ld, n = %ld\n", 
            a,us,alpha,m,n);
        printf("us[0] = %f\n", us[0]);
        printf("a[0] = %f\n", a[0]);
    }
#endif
    int id = blockDim.x * blockIdx.x + threadIdx.x;
    if (id>=m)
        return;
    ElemType tmp = a[id];
#ifdef VALIDATION
    printf("  a[%d] = %f\n", id, tmp);
#endif
    for (long j = 0; j < n; ++j )
    {
        us[j*m+id] += alpha*tmp;
    }
 
}


template<class ElemType>
__global__ void _matrixVectorColumnWiseAddBlockPerRow(
    const ElemType* a,
    ElemType* us,
    ElemType alpha,
    const long m,  //number of rows
    const long n)  //number of cols     
{    
    ElemType tmp;

    if (threadIdx.x==0)
    {
        tmp = a[blockIdx.x];
    }
    __syncthreads();

    int loadPerThread = n/blockDim.x; 

    for (int i= threadIdx.x*loadPerThread; i< (threadIdx.x == blockDim.x - 1 ? n : (threadIdx.x+1)*loadPerThread);++i)
    {
        us[m*blockIdx.x + i] += alpha*tmp;
    }
}



template<class ElemType>
__global__ void _addScaledDifference( 
    ElemType alpha,
    ElemType *a,
    ElemType *b,
    ElemType *c,
    LONG64 N)
{
    LONG64 id = blockDim.x * blockIdx.x + threadIdx.x;
    if (id>=N)
        return;
    c[id] = c[id] + (a[id]-b[id]) * (alpha);
}

template<class ElemType>
__global__ void _assignScaledDifference( 
    ElemType alpha,
    ElemType *a,
    ElemType *b,
    ElemType *c,
    LONG64 N)
{
    LONG64 id = blockDim.x * blockIdx.x + threadIdx.x;
    if (id>=N)
        return;
    c[id] = (a[id]-b[id]) * (alpha);
}

template<class ElemType>
__global__ void _addScaledDifference( 
    ElemType *alpha,
    ElemType *a,
    ElemType *b,
    ElemType *c,
    LONG64 N)
{
    LONG64 id = blockDim.x * blockIdx.x + threadIdx.x;
    if (id>=N)
        return;
    c[id] = c[id] + (a[id]-b[id]) * alpha[0];
}

template<class ElemType>
__global__ void _assignScaledDifference( 
    ElemType *alpha,
    ElemType *a,
    ElemType *b,
    ElemType *c,
    LONG64 N)
{
    LONG64 id = blockDim.x * blockIdx.x + threadIdx.x;
    if (id>=N)
        return;
    c[id] = (a[id]-b[id]) * alpha[0];
}

template<class ElemType>
__global__ void _addElementToElement( 
    const ElemType *a, LONG64 indexA,
    ElemType *c, LONG64 indexC)
{
    LONG64 id = blockDim.x * blockIdx.x + threadIdx.x;
    if (id>0)
        return;
    c[indexC] += a[indexA];
}

template<class ElemType>
__global__ void _assignNumOfDiff( 
    const ElemType *a,
    const ElemType *b,
    ElemType *c,
    LONG64 N)
{
    __shared__ ElemType partialSums[1024];
    partialSums[threadIdx.x]=0;
    //int id = blockDim.x * blockIdx.x + threadIdx.x;
    LONG64 loadPerThread = N/blockDim.x; 
    for (LONG64 i= threadIdx.x*loadPerThread; i< (threadIdx.x == blockDim.x - 1 ? N : (threadIdx.x+1)*loadPerThread);++i)
    {
        partialSums[threadIdx.x]+=(a[i] != b[i]);
    }
    __syncthreads();

    //512
    if (threadIdx.x<512)
    {
        partialSums[threadIdx.x]+=partialSums[threadIdx.x+512];
    }
    __syncthreads();

    //256
    if (threadIdx.x<256)
    {
        partialSums[threadIdx.x]+=partialSums[threadIdx.x+256];
    }
    __syncthreads();

    //128
    if (threadIdx.x<128)
    {
        partialSums[threadIdx.x]+=partialSums[threadIdx.x+128];
    }
    __syncthreads();

    //64
    if (threadIdx.x<64)
    {
        partialSums[threadIdx.x]+=partialSums[threadIdx.x+64];
    }
    __syncthreads();

    //32
    if (threadIdx.x<32)
    {
        partialSums[threadIdx.x]+=partialSums[threadIdx.x+32];
    }
    __syncthreads();

    //16
    if (threadIdx.x<16)
    {
        partialSums[threadIdx.x]+=partialSums[threadIdx.x+16];
    }
    __syncthreads();

    //8
    if (threadIdx.x<8)
    {
        partialSums[threadIdx.x]+=partialSums[threadIdx.x+8];
    }
    __syncthreads();

    //4
    if (threadIdx.x<4)
    {
        partialSums[threadIdx.x]+=partialSums[threadIdx.x+4];
    }
    __syncthreads();

    if (threadIdx.x==0)
    {
        c[0] = partialSums[0]+partialSums[1]+partialSums[2]+partialSums[3];
    }
}


/*template<class ElemType>
__global__ void _assignNumOfDiff( 
ElemType *a,
ElemType *b,
ElemType *c,
long N)
{
//TO DO: replace atomic operation with reduction

__shared__ int totalSum;
if (threadIdx.x == 0) totalSum = 0;
__syncthreads();

int id = blockDim.x * blockIdx.x + threadIdx.x;
if (id>=N)
return;

int localVal = (a[id] != b[id]);
atomicAdd(&totalSum, localVal);
__syncthreads();

c[id] = totalSum;
}*/

template<class ElemType>
__global__ void _scaleArray(
    ElemType alpha,
    ElemType *us,
    LONG64 N)
{
    LONG64 id = blockDim.x * blockIdx.x + threadIdx.x;
    if (id>=N)
        return;
    us[id]=us[id]*alpha;
}


template<class ElemType>
__global__ void _sparseCSRPlusDense(
    ElemType alpha,
    const ElemType* m_dVal,
    const int* m_dRow,
    const int* m_dCol,
    ElemType* pArrayDev,
    LONG64 M)
{
    LONG64 id = blockDim.x * blockIdx.x + threadIdx.x;
    if (id>=M)
        return;
    int start = m_dRow[id];
    int end = m_dRow[id+1];
    for (int _i=start;_i<end;++_i)  //_i is index in m_dVal and m_dCol
    {
        int j = m_dCol[_i];
        pArrayDev[IDX2C(id,j,M)]+=(alpha*m_dVal[_i]);
    }
}

template<class ElemType>
__global__ void _sparseCSRElemMulDense(    
    const ElemType* m_dVal,
    const int* m_dRow,
    const int* m_dCol,
    const ElemType* b,
    ElemType* c,
    LONG64 M)
{
    LONG64 id = blockDim.x * blockIdx.x + threadIdx.x;
    if (id>=M)
        return;
    int start = m_dRow[id];
    int end = m_dRow[id+1];
    for (int _i=start;_i<end;++_i)  //_i is index in m_dVal and m_dCol
    {
        int j = m_dCol[_i];
        c[IDX2C(id,j,M)]=b[IDX2C(id,j,M)]*m_dVal[_i];
    }
}


//c = alpha * op(a) * op(b) + beta*c
//this function can be further improved by using shared memory
template<class ElemType>
__global__ void _denseMultSparseCSCAndWeightedAddToDense(
    int m, //rowDense
    int n,   //colSparse
    ElemType alpha,
    const ElemType* a,  //dense
    const ElemType* bnzValues,  //sparse nz values
    const GPUSPARSE_INDEX_TYPE* rowIndex,
    const GPUSPARSE_INDEX_TYPE* colCSCIndex,
    ElemType beta,
    ElemType* c  //dense target
    )
{
    LONG64 id = blockDim.x * blockIdx.x + threadIdx.x;
    if (id >= m*n)  
        return;

    int colInC = id / m;
    int rowInC = id - colInC * m;

    int start = colCSCIndex[colInC]; 
    int end = colCSCIndex[colInC + 1];

    ElemType s = 0;
   for (int j = start; j<end; j++)  //j points to the value
    {
        int i = rowIndex[j];
        s += a[IDX2C(rowInC, i, m)] * bnzValues[j];
    }
    c[IDX2C(rowInC, colInC, m)] = alpha * s + beta * c[IDX2C(rowInC, colInC, m)];
}

//called before _determineBlockIds and _denseMulSparseCSCTransposeToSparseBlockCol to determine which columns have values and
//what's the mapping from the column id in the resulted SparseBlockCol format to the column id in the dense format
//input: rowIndexes: the row indexes of the CSC sparse matrix to be multiplied with
//blockIDs: the blockID mapping in the resulting matrix; 
//nnz: number of nonzero value or the size of rowIndexes;
template<class ElemType>
__global__ void _findColsWithValues(
    const GPUSPARSE_INDEX_TYPE* rowIndexes, GPUSPARSE_INDEX_TYPE* blockIds, const size_t nnz)
{
    const size_t index = blockIdx.x * blockDim.x + threadIdx.x;
    if (index >= nnz)
        return;

    blockIds[rowIndexes[index]] = 1; //this row has value.
}

//called before _denseMulSparseCSCTransposeToSparseBlockCol and after _findColsWithValuesto determine which columns have values and
//what's the mapping from the column id in the resulted SparseBlockCol format to the column id in the dense format
//input: rowIndexes: the row indexes of the CSC sparse matrix to be multiplied with
//blockId2Col: the blockID to colum id mapping in the resulting matrix; 
//col2BlockId: the col2BlockId to blockID mapping in the resulting matrix; 
//numCols: number of columns in the resulting matrix or the size of blockIDs
//blockSize: return the blockSize with values, *blockSize must be zero before passed in.
template<class ElemType>
__global__ void _determineBlockIds(
    GPUSPARSE_INDEX_TYPE* blockId2Col, GPUSPARSE_INDEX_TYPE*col2BlockId, const size_t numCols, size_t* blockSize)
{
    const size_t index = blockIdx.x * blockDim.x + threadIdx.x;
    if (index >= numCols)
        return;

    size_t blockIndex = numCols;
    if (blockId2Col[index] > 0)
    {
        blockIndex = atomicAdd((unsigned int *)blockSize, (unsigned int)1);
        col2BlockId[index] = blockIndex;
    }

    __syncthreads();

    if (blockIndex < numCols)
        blockId2Col[blockIndex] = index;
}

// backward pass from hidden layer to feature weight
//result (sparse BlockCol)= alpha * (lhs (dense) X rhs^T (sparse CSC)
//assume resultValues are 0-initialized
template<class ElemType>
__global__ void _denseMulSparseCSCTransposeToSparseBlockCol2(
    const ElemType alpha,
    const ElemType* lhsValues,
    const size_t numRowsLhs,
    const size_t numColsRhs,
    const ElemType* rhsNZValues,
    const GPUSPARSE_INDEX_TYPE* rhsRows,
    const GPUSPARSE_INDEX_TYPE* rhsCols,
    const GPUSPARSE_INDEX_TYPE* col2blockIds,
    ElemType* resultValues)
{
    const LONG64 index = blockIdx.x * blockDim.x + threadIdx.x;
    const LONG64 lhsCol = index / numRowsLhs; //rhsCol == lhsCol
    if (lhsCol >= numColsRhs)
        return;
    const LONG64 lhsRow = index - numRowsLhs*lhsCol; //resultRow == lhsRow

    //each thread handles one [row, col] combination
    ElemType lhsValue = alpha*lhsValues[IDX2C(lhsRow, lhsCol, numRowsLhs)];

    LONG64 start = rhsCols[lhsCol]; //rhsCol == lhsCol
    LONG64 end = rhsCols[lhsCol + 1];

    for (LONG64 p = start; p < end; p++)
    {
        LONG64 rhsRow = rhsRows[p];
        ElemType rhsVal = rhsNZValues[p];
        LONG64 resultCol = col2blockIds[rhsRow]; //resultCol == rhsRow maps to columnid 

        //assume resultValues are 0-initialized
        atomicAdd(&resultValues[IDX2C(lhsRow, resultCol, numRowsLhs)], lhsValue * rhsVal);
    }
}

// backward pass from hidden layer to feature weight
//result (sparse BlockCol)= alpha * (lhs (dense) X rhs^T (sparse CSC)
//assume resultValues are 0-initialized
template<class ElemType>
__global__ void _denseMulSparseCSCTransposeToSparseBlockCol(
    const ElemType alpha,
    const ElemType* lhsValues,
    const size_t numRowsLhs,
    const size_t numColsRhs,
    const ElemType* rhsNZValues,
    const GPUSPARSE_INDEX_TYPE* rhsRows,
    const GPUSPARSE_INDEX_TYPE* rhsCols,
    const GPUSPARSE_INDEX_TYPE* rhsRowIdx,
    ElemType* resultValues,
    GPUSPARSE_INDEX_TYPE* resultBlockIds)
{
    const LONG64 index = blockIdx.x * blockDim.x + threadIdx.x;
    const LONG64 lhsCol = index / numRowsLhs; //rhsCol == lhsCol
    if (lhsCol >= numColsRhs)
        return;
    const LONG64 lhsRow = index - numRowsLhs*lhsCol; //resultRow == lhsRow

    //each thread handles one [row, col] combination
    ElemType lhsValue = alpha*lhsValues[IDX2C(lhsRow, lhsCol, numRowsLhs)];

    LONG64 start = rhsCols[lhsCol]; //rhsCol == lhsCol
    LONG64 end = rhsCols[lhsCol + 1];

    for (LONG64 p = start; p < end; p++)
    {
        LONG64 rhsRow = rhsRows[p]; 
        ElemType rhsVal = rhsNZValues[p];
        LONG64 resultCol = rhsRowIdx[p]; //resultCol == rhsRow maps to columnid 
        resultBlockIds[resultCol] = rhsRow;  //indicate which colmn it actually points to

        //assume resultValues are 0-initialized
        atomicAdd(&resultValues[IDX2C(lhsRow, resultCol, numRowsLhs)], lhsValue * rhsVal);
    }
}


// gradients update
template<class ElemType>
__global__ void _scaleSparseBlockAndAddToDense(    
    const ElemType alpha,
    const bool blockCol, //true if blockRow
    const size_t numRows,
    const size_t numCols,
    const size_t numBlocks,
    const ElemType* lhsValues,  //lhs is blockCol or blockRow
    const GPUSPARSE_INDEX_TYPE* blockIds,
    ElemType* rhs)
{
    const LONG64 index = blockIdx.x * blockDim.x + threadIdx.x;
    LONG64 row, col;
    if (blockCol)
    {
        const LONG64 blockId = index / numRows;
        if (blockId >= numBlocks)
            return;
        row = index - numRows* blockId;
        col = blockIds[blockId];
    }
    else
    {
        const LONG64 blockId = index / numCols;
        if (blockId >= numBlocks)
            return;
        col = index - numCols* blockId;
        row = blockIds[blockId];
    }
    rhs[IDX2C(row, col, numRows)] += alpha * lhsValues[index];
}

// compute predictions in cross entory node
template<class ElemType>
__global__ void _computePrediction(
    int nv,
    const ElemType* a,
    int numrows,
    const ElemType* weight,   
    int nrs,
    int labelSize,
    const GPUSPARSE_INDEX_TYPE* labelRow,
    const size_t* block2Id,
    const ElemType* cls,
    const ElemType* idx2cls,    
    ElemType* val,
    GPUSPARSE_INDEX_TYPE* row,
    GPUSPARSE_INDEX_TYPE* pb)
{
    // get label block id
    int id = -1;
    int offset = -1;
    for(int i = 1; i < labelSize; i++) 
    {
        if (blockIdx.x < block2Id[i]) 
        {
            id = i-1;
            offset = blockIdx.x - block2Id[i-1];
            break;
        }
    }
    if( id == -1) 
    {
        id = labelSize-1;
        offset = blockIdx.x - block2Id[labelSize-1];
    }

    int t = labelRow[id];
    int iStt;
    int iEnd;
    if(t < nv) 
    {
        int clsid = idx2cls[t];
        iStt = cls[IDX2C(0, clsid, 2)];
        iEnd = cls[IDX2C(1, clsid, 2)];
    } 
    else 
    {
        iStt = nv;
        iEnd = nrs;
    }
    int i = iStt + offset;
    int j = id /2;
    
    int loadPerThread = (numrows+blockDim.x-1)/blockDim.x;
    int tStart = loadPerThread * threadIdx.x;
    int tEnd = min((int)numrows, loadPerThread + tStart);

    ElemType v = 0.0;
    for (int h = tStart; h < tEnd; h++)
    {
        v += weight[IDX2C(i,h,nrs)] * a[IDX2C(h,j,numrows)]; 
    }
    atomicAdd(&val[blockIdx.x], v);
    row[blockIdx.x] = i;

    if(blockIdx.x == 0 && threadIdx.x == 0) 
        pb[0] = 0;
    
    if((threadIdx.x == 0) && (i == iEnd-1) && (i >= nv)) 
        pb[j+1] = blockIdx.x+1;
}

// normalize predictions in cross entropy node
template<class ElemType>
__global__ void _normalizePrediction(
    const size_t labelSize,
    const size_t expandedLabelSize,
    const GPUSPARSE_INDEX_TYPE* labelRow,
    const size_t* block2Id,    
    const GPUSPARSE_INDEX_TYPE* row,
    ElemType* val,
    ElemType* entropyScore)
{    
    __shared__ ElemType partials[512];
    partials[threadIdx.x] = 0;

    int p = blockIdx.x;
    int t = labelRow[p];
    int start = block2Id[p];
    int end;
    if(p == labelSize -1) 
    {
        end = expandedLabelSize;
    } 
    else 
    {
        end = block2Id[p+1];
    }
    int len = end - start;

    int loadPerThread = (len+blockDim.x-1)/blockDim.x;
    int tStart = loadPerThread * threadIdx.x;
    int tLen = min((int)len, loadPerThread + tStart);

    for(int i = start + tStart; i < start + tLen; i++) 
    {
        partials[threadIdx.x] += exp(val[i]);
    }

    __syncthreads();

    // now sum up the objective function
    int nTotalThreads = blockDim.x;

    while (nTotalThreads >1)
    {
        int halfPoint = (nTotalThreads >> 1);

        if (threadIdx.x < halfPoint)
            partials[threadIdx.x] += partials[threadIdx.x+halfPoint];

        __syncthreads();

        nTotalThreads = (nTotalThreads>>1);
    }
    
    for(int i = start + tStart; i < start + tLen; i++) 
    {
        val[i] = log(exp(val[i])/partials[0]);
        if(row[i] == t) 
        {
            atomicAdd(entropyScore, -val[i]);
            val[i] *= -1;
        }
    }
}

// compute prediction error in cross entropy node
template<class ElemType>
__global__ void _computePredictionError(
    ElemType* val,
    int N)
{    
    int p = blockDim.x * blockIdx.x + threadIdx.x;
    if (p>=N)
        return;

    if(val[p] < 0) 
        val[p] = exp(val[p]); //negative;
    else 
        val[p] = exp(-val[p])-1; //positive
}

// compute gradients of input in cross entropy node
template<class ElemType>
__global__ void _computeGradientOfInput(
    const ElemType* val,
    const GPUSPARSE_INDEX_TYPE* row,
    const GPUSPARSE_INDEX_TYPE* pb,    
    ElemType* weight,
    size_t nrs,
    ElemType* grd,
    size_t numrows)
{        
    int h = blockIdx.x%numrows;
    int j = blockIdx.x/numrows;

    int start = pb[j];
    int end = pb[j+1];
    int len = end - start;
    
    int load = (len+blockDim.x-1)/blockDim.x;
    int pStart = start + load * threadIdx.x;
    int pEnd = start + min(len, load * (threadIdx.x+1));

    ElemType sum = 0;
    for(int p = pStart; p < pEnd; p++) 
    {
        int i = row[p];
        sum += val[p] * weight[IDX2C(i, h, nrs)]; 
    }    

    atomicAdd(&grd[IDX2C(h,j,numrows)], sum);
}


template<class ElemType>
__global__ void computeNCEForwardProp(
    const ElemType* val,
    const int* col,
    int numRows,
    int sampleCount,
    const ElemType* a,
    int numCols_a,
    const ElemType* b,
    ElemType* res)
{
    // val and col are in CSR format
    // val is an array contains log_Pn(w). To differentiate positive and negative samples, 
    // we store log_Pn(w) as it is for positive samples, and -log_Pn(w) for negative samples
    // col is an array contains index of the word samples
    // a is a matrix in column major format contains output from hidden layer
    // b is the weight matrix for output layer
    // res is the buffer to store computed output (sparse)

    // follow the convention, this kernel must be run on 512 threads per block
    __shared__ ElemType partials[512];
    partials[threadIdx.x] = 0;

    // determine the elements to be handled by this block
    int total = numRows * sampleCount;
    int loadPerBlock = (total + gridDim.x - 1) / gridDim.x;

    int start = loadPerBlock * blockIdx.x;
    int end = min(total, loadPerBlock * (blockIdx.x + 1));

    for (int i = start; i < end; i++)
    {
        int colIndex = col[i];
        int rowIndex = i / sampleCount;

        int loadPerThread = (numCols_a + blockDim.x - 1) / blockDim.x;
        int tstart = loadPerThread * threadIdx.x;
        int tend = min(numCols_a, loadPerThread * (threadIdx.x + 1));

        for (int j = tstart; j < tend; j++)
            partials[threadIdx.x] = a[IDX2C(rowIndex, j, numRows)] * b[IDX2C(j, colIndex, numCols_a)];

        __syncthreads();

        // sum up
        int nTotalThreads = blockDim.x;

        while (nTotalThreads >1)
        {
            int halfPoint = (nTotalThreads >> 1);

            if (threadIdx.x < halfPoint)
                partials[threadIdx.x] += partials[threadIdx.x + halfPoint];

            __syncthreads();

            nTotalThreads = (nTotalThreads >> 1);
        }

        if (threadIdx.x == 0)
            res[i] = partials[0];
    }
}


template<class ElemType>
__global__ void _computeNceOutput(
    const ElemType* col,
    int numRows,
    int sampleCount,
    const ElemType* a,
    int numCols_a,
    const ElemType* b,
    ElemType* res)
{
    // val and col are in CSR format
    // val is an array contains log_Pn(w). To differentiate positive and negative samples, 
    // we store log_Pn(w) as it is for positive samples, and -log_Pn(w) for negative samples
    // col is an array contains index of the word samples
    // a is a matrix in column major format contains output from hidden layer
    // b is the weight matrix for output layer
    // res is the buffer to store computed output (sparse)

    // follow the convention, this kernel must be run on 512 threads per block
    __shared__ ElemType partials[512];
    partials[threadIdx.x] = 0;

    //threadIdx.x range from[0 ~ 512)
    //blockIdx.x range from[0 ~ nnz)
    //blockDim.x equal to 512
    //gridDim.x equal to nnz

    // determine the elements to be handled by this block
    int total = numRows * sampleCount;
    int loadPerBlock = (total + gridDim.x - 1) / gridDim.x;

    int start = loadPerBlock * blockIdx.x;
    int end = min(total, loadPerBlock * (blockIdx.x + 1));

    for (int i = start; i < end; i++)
    {
        int colIndex = (int)col[2 * i];
        int rowIndex = i / sampleCount;

        int loadPerThread = (numCols_a + blockDim.x - 1) / blockDim.x;
        int tstart = loadPerThread * threadIdx.x;
        int tend = min(numCols_a, loadPerThread * (threadIdx.x + 1));

        for (int j = tstart; j < tend; j++)
            partials[threadIdx.x] = a[IDX2C(rowIndex, j, numRows)] * b[IDX2C(j, colIndex, numCols_a)];

        __syncthreads();

        // sum up
        int nTotalThreads = blockDim.x;

        while (nTotalThreads >1)
        {
            int halfPoint = (nTotalThreads >> 1);

            if (threadIdx.x < halfPoint)
                partials[threadIdx.x] += partials[threadIdx.x + halfPoint];

            __syncthreads();

            nTotalThreads = (nTotalThreads >> 1);
        }

        if (threadIdx.x == 0)
            res[i] = partials[0];
    }
}

template<class ElemType>
__global__ void _computeNceOutput(
    const ElemType* val,
    const int* col,
    int numRows,
    int sampleCount,
    const ElemType* a,
    int numCols_a,
    const ElemType* b,
    ElemType* res)
{
    // val and col are in CSR format
    // val is an array contains log_Pn(w). To differentiate positive and negative samples, 
    // we store log_Pn(w) as it is for positive samples, and -log_Pn(w) for negative samples
    // col is an array contains index of the word samples
    // a is a matrix in column major format contains output from hidden layer
    // b is the weight matrix for output layer
    // res is the buffer to store computed output (sparse)

    // follow the convention, this kernel must be run on 512 threads per block
    __shared__ ElemType partials[512];
    partials[threadIdx.x] = 0;

    //threadIdx.x range from[0 ~ 512)
    //blockIdx.x range from[0 ~ nnz)
    //blockDim.x equal to 512
    //gridDim.x equal to nnz

    // determine the elements to be handled by this block
    int total = numRows * sampleCount;
    int loadPerBlock = (total + gridDim.x - 1) / gridDim.x;

    int start = loadPerBlock * blockIdx.x;
    int end = min(total, loadPerBlock * (blockIdx.x + 1));

    for (int i = start; i < end; i++)
    {
        int colIndex = col[i];
        int rowIndex = i / sampleCount;

        int loadPerThread = (numCols_a + blockDim.x - 1) / blockDim.x;
        int tstart = loadPerThread * threadIdx.x;
        int tend = min(numCols_a, loadPerThread * (threadIdx.x + 1));

        for (int j = tstart; j < tend; j++)
            partials[threadIdx.x] = a[IDX2C(rowIndex, j, numRows)] * b[IDX2C(j, colIndex, numCols_a)];

        __syncthreads();

        // sum up
        int nTotalThreads = blockDim.x;

        while (nTotalThreads >1)
        {
            int halfPoint = (nTotalThreads >> 1);

            if (threadIdx.x < halfPoint)
                partials[threadIdx.x] += partials[threadIdx.x + halfPoint];

            __syncthreads();

            nTotalThreads = (nTotalThreads >> 1);
        }

        if (threadIdx.x == 0)
            res[i] = partials[0];
    }
}


template<class ElemType>
__global__ void _assignNoiseContrastiveEstimation(
    const ElemType* val,
    int numRows,
    int sampleCount,
    const ElemType* a,
    int width, // number of columns in a
    const ElemType* b,
    const ElemType* tmp,
    ElemType* c) // run on 512 threads per block
{
    // val and col are in CSR format
    // val is an array contains log_Pn(w). To differentiate positive and negative samples, 
    // we store log_Pn(w) as it is for positive samples, and -log_Pn(w) for negative samples
    // col is an array contains index of the word samples
    // a is a matrix in column major format contains output from hidden layer
    // b is the weight matrix for output layer
    // tmp is the buffer that stores NCE output calculated from _computeNceOutput
    // c is the matrix to store objective

    __shared__ ElemType partials[512];
    partials[threadIdx.x] = 0;

    int total = numRows * sampleCount;
    int loadPerThread = (total + 511) / 512;

    // find out the items this thread is responsible for
    int start = loadPerThread * threadIdx.x;
    int end = min(total, loadPerThread * (threadIdx.x + 1));

    for (int i = start; i < end; i++)
    {
        //int colIndex = col[i];
        //int rowIndex = i / sampleCount;

        // add to objective
        ElemType log_pnw = val[2 * i + 1];
        if (log_pnw < 0) // positive sample: log(pw / (pw + k * pnw))
        {
            ElemType den = tmp[i];
            logadd(den, log((ElemType)(sampleCount - 1)) + log_pnw);
            partials[threadIdx.x] += (tmp[i] - den);
        }
        else // negative sample: log(k * pnw / (pw + k * pnw))
        {
            ElemType nom = log((ElemType)(sampleCount - 1)) - log_pnw;
            ElemType den = nom;
            logadd(den, tmp[i]);
            partials[threadIdx.x] += (nom - den);
        }
    }

    __syncthreads();

    // now sum up the objective function
    int nTotalThreads = blockDim.x;

    while (nTotalThreads >1)
    {
        int halfPoint = (nTotalThreads >> 1);

        if (threadIdx.x < halfPoint)
            partials[threadIdx.x] += partials[threadIdx.x + halfPoint];

        __syncthreads();

        nTotalThreads = (nTotalThreads >> 1);
    }

    if (threadIdx.x == 0)
        c[0] = -partials[0];
}

template<class ElemType>
__global__ void _assignNoiseContrastiveEstimation(
    const ElemType* val,
    const int* col,
    int numRows,
    int sampleCount,
    const ElemType* a,
    int width, // number of columns in a
    const ElemType* b,
    const ElemType* tmp,
    ElemType* c) // run on 512 threads per block
{
    // val and col are in CSR format
    // val is an array contains log_Pn(w). To differentiate positive and negative samples, 
    // we store log_Pn(w) as it is for positive samples, and -log_Pn(w) for negative samples
    // col is an array contains index of the word samples
    // a is a matrix in column major format contains output from hidden layer
    // b is the weight matrix for output layer
    // tmp is the buffer that stores NCE output calculated from _computeNceOutput
    // c is the matrix to store objective

    __shared__ ElemType partials[512];
    partials[threadIdx.x] = 0;

    int total = numRows * sampleCount;
    int loadPerThread = (total + 511) / 512;

    // find out the items this thread is responsible for
    int start = loadPerThread * threadIdx.x;
    int end = min(total, loadPerThread * (threadIdx.x + 1));

    for (int i = start; i < end; i++)
    {
        //int colIndex = col[i];
        //int rowIndex = i / sampleCount;

        // add to objective
        ElemType log_pnw = val[i];
        if (log_pnw < 0) // positive sample: log(pw / (pw + k * pnw))
        {
            ElemType den = tmp[i];
            logadd(den, log((ElemType)(sampleCount - 1)) + log_pnw);
            partials[threadIdx.x] += (tmp[i] - den);
        }
        else // negative sample: log(k * pnw / (pw + k * pnw))
        {
            ElemType nom = log((ElemType)(sampleCount - 1)) - log_pnw;
            ElemType den = nom;
            logadd(den, tmp[i]);
            partials[threadIdx.x] += (nom - den);
        }
    }

    __syncthreads();

    // now sum up the objective function
    int nTotalThreads = blockDim.x;

    while (nTotalThreads >1)
    {
        int halfPoint = (nTotalThreads >> 1);

        if (threadIdx.x < halfPoint)
            partials[threadIdx.x] += partials[threadIdx.x + halfPoint];

        __syncthreads();

        nTotalThreads = (nTotalThreads >> 1);
    }

    if (threadIdx.x == 0)
        c[0] = -partials[0];
}

template<class ElemType>
__global__ void _computeNceError(
    const ElemType* val,

    int numRows,
    int sampleCount,
    ElemType* tmp) // run on one block 
{
    int total = numRows * sampleCount;
    int loadPerThread = (total + blockDim.x - 1) / blockDim.x;

    // find out the items this thread is responsible for
    int start = loadPerThread * threadIdx.x;
    int end = min(total, loadPerThread * (threadIdx.x + 1));

    for (int i = start; i < end; i++)
    {
        ElemType ac = tmp[i]; // precalculated NCE output
        ElemType log_pnw = val[2 * i + 1];

        ElemType er = 0;
        if (log_pnw < 0) // positive sample: k * pnw / (pw + k * pnw)
        {
            ElemType nom = log((ElemType)(sampleCount - 1)) + log_pnw;
            logadd(ac, nom);
            er = -1 * exp(nom - ac);

        }
        else // negative sample: pw / (pw + k * pnw);
        {
            logadd(ac, log((ElemType)(sampleCount - 1)) - log_pnw);
            er = exp(tmp[i] - ac);
        }

        tmp[i] = er;
    }
}

template<class ElemType>
__global__ void _computeNceError(
    const ElemType* val,
    const int* col,
    int numRows,
    int sampleCount,
    ElemType* tmp) // run on one block 
{
    int total = numRows * sampleCount;
    int loadPerThread = (total + blockDim.x - 1) / blockDim.x;

    // find out the items this thread is responsible for
    int start = loadPerThread * threadIdx.x;
    int end = min(total, loadPerThread * (threadIdx.x + 1));

    for (int i = start; i < end; i++)
    {
        ElemType ac = tmp[i]; // precalculated NCE output
        ElemType log_pnw = val[i];

        ElemType er = 0;
        if (log_pnw < 0) // positive sample: k * pnw / (pw + k * pnw)
        {
            ElemType nom = log((ElemType)(sampleCount - 1)) + log_pnw;
            logadd(ac, nom);
            er = -1 * exp(nom - ac);

        }
        else // negative sample: pw / (pw + k * pnw);
        {
            logadd(ac, log((ElemType)(sampleCount - 1)) - log_pnw);
            er = exp(tmp[i] - ac);
        }

        tmp[i] = er;
    }
}

template<class ElemType>
__global__ void _assignNceDerivativeInJbor(
    const ElemType* val,
    const int* col,
    const int* colndx,
    int numRows,
    int sampleCount,
    const ElemType* a,
    int width, // number of columns in a
    const ElemType* b,
    const ElemType* tmp,
    unsigned char* c,
    size_t jborBlockSize)
{
    // val and col are CSR format sparse matrix for label
    // val is an array contains log_Pn(w). To differentiate positive and negative samples
    // we store log_Pn(w) as it is for positive samples, and -log_Pn(w) for negative samples
    // col is an array contains index of the word samples
    // a is a matrix in column major format contains output from hidden layer
    // b is the weight matrix for output layer
    // tmp is a matrix of precalculated error
    // c is the output array to store intermediate results


    /*
    int total = numRows * sampleCount;
    int loadPerBlock = (total + gridDim.x - 1) / gridDim.x;

    // find out the items this block is responsible for
    int start = loadPerBlock * blockIdx.x;
    int end = min(total, loadPerBlock * (blockIdx.x + 1));

    for (int i = start; i < end; i++)
    {
    int colIndex = col[i];
    int rowIndex = i / sampleCount;

    ElemType er = tmp[i]; // precalculated error for this output node
    ElemType log_pnw = val[i];

    // calculate gradients
    int loadPerThread = (width + blockDim.x - 1) / blockDim.x;
    int tstart = loadPerThread * threadIdx.x;
    int tend = min(width, loadPerThread*(threadIdx.x + 1));
    for (int j = tstart; j < tend; j++)
    {
    ElemType val = er * a[IDX2C(rowIndex, j, numRows)];

    unsigned char* pj = c + (j*jborBlockSize + colndx[i]) * sizeof(JborRecord<ElemType>);
    atomicExch((int*)pj, colIndex);
    atomicAdd((ElemType*)(pj + sizeof(int)), val);
    }
    }*/
}

template<class ElemType>
__global__ void _assignNceDerivative(
    const ElemType* val,
    int numRows,
    int sampleCount,
    const ElemType* a,
    int width, // number of columns in a
    const ElemType* b,
    const ElemType* tmp,
    ElemType* c,
    size_t inputIndex)
{
    // val and col are CSR format sparse matrix for label
    // val is an array contains log_Pn(w). To differentiate positive and negative samples
    // we store log_Pn(w) as it is for positive samples, and -log_Pn(w) for negative samples
    // col is an array contains index of the word samples
    // a is a matrix in column major format contains output from hidden layer
    // b is the weight matrix for output layer
    // tmp is a matrix of precalculated error
    // c is the output matrix to store calculated gradients

    int total = numRows * sampleCount;
    int loadPerBlock = (total + gridDim.x - 1) / gridDim.x;

    // find out the items this block is responsible for
    int start = loadPerBlock * blockIdx.x;
    int end = min(total, loadPerBlock * (blockIdx.x + 1));

    for (int i = start; i < end; i++)
    {
        int colIndex = (int)val[2 * i];
        int rowIndex = i / sampleCount;

        ElemType er = tmp[i]; // precalculated error for this output node
        //ElemType log_pnw = val[2 * i + 1];

        // calculate gradients
        int loadPerThread = (width + blockDim.x - 1) / blockDim.x;
        int tstart = loadPerThread * threadIdx.x;
        int tend = min(width, loadPerThread*(threadIdx.x + 1));

        if (inputIndex == 1) // hidden layer output
        {
            for (int j = tstart; j < tend; j++)
            {
                ElemType val = er * b[IDX2C(j, colIndex, width)];
                atomicAdd(c + IDX2C(rowIndex, j, numRows), val);
                //c[IDX2C(rowIndex, j, numRows)] += val;
            }
        }
        else // weight
        {
            for (int j = tstart; j < tend; j++)
            {
                ElemType val = er * a[IDX2C(rowIndex, j, numRows)];
                atomicAdd(c + IDX2C(j, colIndex, width), val);
                //c[IDX2C(j, colIndex, width)] += val;
            }
        }
    }
}

// compute gradients of weights in cross entropy node
template<class ElemType>
__global__ void _computeGradientOfWeight(
    const ElemType* val,
    const GPUSPARSE_INDEX_TYPE* row,
    const GPUSPARSE_INDEX_TYPE* pb,
    size_t mb,
    size_t nv,
    const GPUSPARSE_INDEX_TYPE* labelRow,
    const size_t* labelBlock2UniqId,
    const ElemType* cls,
    const ElemType* idx2cls,
    ElemType* input,
    size_t nrs,
    ElemType* blockVal,
    GPUSPARSE_INDEX_TYPE* blockIds)
{
    int p = blockIdx.x;
    ElemType v = val[p];
    int i = row[p];
    int j = -1;
    for(int k = 1; k < mb; k++) 
    {
        if( p < pb[k]) 
        {
            j = k-1;
            break;
        }
    }
    if( j == -1) 
    {
        j = mb-1;
    }

    //figure out blocks
    int bId = i < nv ? 2*j : 2*j+1;
    int t = labelRow[bId];
    int iStt;
    if(t < nv) 
    {
        int clsid = idx2cls[t];
        iStt = cls[IDX2C(0, clsid, 2)];
    } 
    else 
    {
        iStt = nv;
    }
    int offset = i - iStt;
    int ii = labelBlock2UniqId[bId] + offset;

    int load = (nrs+blockDim.x-1)/blockDim.x;
    int pStart = load * threadIdx.x;
    int pEnd = min((int)nrs, load + pStart);

    for(int h = pStart; h < pEnd; h++) 
    {        
        ElemType temp = v * input[IDX2C(h, j, nrs)];    
        atomicAdd(&blockVal[ii*nrs+h], temp);
        blockIds[ii] = i;
    }
}

// used in clipping gradients
template<class ElemType>
__global__ void _inplaceTruncate(
    ElemType* a,
    const ElemType threshold,
    const LONG64 N)
{
    LONG64 id = blockDim.x * blockIdx.x + threadIdx.x;
    if (id>=N)
        return;
    ElemType locThresholdPos = abs(threshold);
    ElemType locTHresholdNeg = -locThresholdPos; 
    if (a[id] > locThresholdPos)
    {
        a[id] = locThresholdPos;
    }
    else if(a[id] < locTHresholdNeg)
    {
        a[id] = locTHresholdNeg;
    }
}

template<class ElemType>
__global__ void _inplaceSoftThreshold(
    ElemType* a,
    const ElemType threshold,
    const LONG64 N)
{
    LONG64 id = blockDim.x * blockIdx.x + threadIdx.x;
    if (id >= N)
        return;

    if (a[id] > threshold)
    {
        a[id] -= threshold;
    }
    else if (a[id] < -threshold)
    {
        a[id] += threshold;
    }
    else
        a[id] = 0;
}


template<class ElemType>
__global__ void _normalGradForSparseBlock(
    const ElemType momentum,
    const bool blockCol, //true if blockRow
    const size_t numRows,
    const size_t numCols,
    const size_t numBlocks,
    ElemType* lhsValues,  //lhs is blockCol or blockRow
    const GPUSPARSE_INDEX_TYPE* blockIds,
    ElemType* rhs)
{
    const LONG64 index = blockIdx.x * blockDim.x + threadIdx.x;
    LONG64 row, col;
    if (blockCol)
    {
        const LONG64 blockId = index / numRows;
        if (blockId >= numBlocks)
            return;
        row = index - numRows* blockId;
        col = blockIds[blockId];
    }
    else
    {
        const LONG64 blockId = index / numCols;
        if (blockId >= numBlocks)
            return;
        col = index - numCols* blockId;
        row = blockIds[blockId];
    }
    rhs[IDX2C(row, col, numRows)] = (1 - momentum)*lhsValues[index] + momentum*rhs[IDX2C(row, col, numRows)];
    lhsValues[index] = rhs[IDX2C(row, col, numRows)];
}

static __inline__ __device__ double atomicAdd(double* address, double val)
{
    unsigned long long int* address_as_ull = (unsigned long long int*)address;
    unsigned long long int old = *address_as_ull, assumed;

    do {
        assumed = old;
        old = atomicCAS(address_as_ull, assumed, __double_as_longlong(val + __longlong_as_double(assumed)));
    } while (assumed != old);

    return __longlong_as_double(old);
}

template<class ElemType>
static __inline__ __device__ ElemType logadd(ElemType x, ElemType y)
{
    ElemType temp, diff, z; 

    if (x < y) 
    {
        temp = x; x = y; y = temp;
    }
    diff = y - x; 
    if (diff < MINLOGEXP)
    {
        return (x < LSMALL)?LZERO:x;
    }
    else
    {
        z = exp(diff);
        return x + log(1.0 + z);
    }
}

//This function should be called with 1024 threads per block and 1 block
//THIS IS NOT THE MOST EFFICIENT IMPLEMENTATION!!!
template<class ElemType>
__global__ void _reductionSum(
    const ElemType* data,
    ElemType *sum,
    LONG64 N)
{

    __shared__ ElemType partialSums[1024];
    partialSums[threadIdx.x]=0;
    //int id = blockDim.x * blockIdx.x + threadIdx.x;
    LONG64 loadPerThread = N/blockDim.x; 
    for (LONG64 i= threadIdx.x*loadPerThread; i< (threadIdx.x == blockDim.x - 1 ? N : (threadIdx.x+1)*loadPerThread);++i)
    {
        partialSums[threadIdx.x]+=data[i];
    }
    __syncthreads();

    //512
    if (threadIdx.x<512)
    {
        partialSums[threadIdx.x]+=partialSums[threadIdx.x+512];
    }
    __syncthreads();

    //256
    if (threadIdx.x<256)
    {
        partialSums[threadIdx.x]+=partialSums[threadIdx.x+256];
    }
    __syncthreads();

    //128
    if (threadIdx.x<128)
    {
        partialSums[threadIdx.x]+=partialSums[threadIdx.x+128];
    }
    __syncthreads();

    //64
    if (threadIdx.x<64)
    {
        partialSums[threadIdx.x]+=partialSums[threadIdx.x+64];
    }
    __syncthreads();

    //32
    if (threadIdx.x<32)
    {
        partialSums[threadIdx.x]+=partialSums[threadIdx.x+32];
    }
    __syncthreads();

    //16
    if (threadIdx.x<16)
    {
        partialSums[threadIdx.x]+=partialSums[threadIdx.x+16];
    }
    __syncthreads();

    //8
    if (threadIdx.x<8)
    {
        partialSums[threadIdx.x]+=partialSums[threadIdx.x+8];
    }
    __syncthreads();

    //4
    if (threadIdx.x<4)
    {
        partialSums[threadIdx.x]+=partialSums[threadIdx.x+4];
    }
    __syncthreads();

    if (threadIdx.x==0)
    {
        sum[0] = partialSums[0]+partialSums[1]+partialSums[2]+partialSums[3];
    }
}

//This function should be called with 1024 threads per block and 1 block
//THIS IS NOT THE MOST EFFICIENT IMPLEMENTATION!!!
template<class ElemType>
__global__ void _reductionSumAndAssign(
    ElemType* toAssign,
    const ElemType* data,
    LONG64 N, //length of data
    LONG64 M) //length of toAssign
{
    __shared__ ElemType partialSums[1024];
    __shared__ ElemType res;
    partialSums[threadIdx.x]=0;
    //int id = blockDim.x * blockIdx.x + threadIdx.x;
    LONG64 loadPerThread = N/blockDim.x; 
    for (LONG64 i= threadIdx.x*loadPerThread; i< (threadIdx.x == blockDim.x - 1 ? N : (threadIdx.x+1)*loadPerThread);++i)
    {
        partialSums[threadIdx.x]+=data[i];
    }
    __syncthreads();

    //512
    if (threadIdx.x<512)
    {
        partialSums[threadIdx.x]+=partialSums[threadIdx.x+512];
    }
    __syncthreads();

    //256
    if (threadIdx.x<256)
    {
        partialSums[threadIdx.x]+=partialSums[threadIdx.x+256];
    }
    __syncthreads();

    //128
    if (threadIdx.x<128)
    {
        partialSums[threadIdx.x]+=partialSums[threadIdx.x+128];
    }
    __syncthreads();

    //64
    if (threadIdx.x<64)
    {
        partialSums[threadIdx.x]+=partialSums[threadIdx.x+64];
    }
    __syncthreads();

    //32
    if (threadIdx.x<32)
    {
        partialSums[threadIdx.x]+=partialSums[threadIdx.x+32];
    }
    __syncthreads();

    //16
    if (threadIdx.x<16)
    {
        partialSums[threadIdx.x]+=partialSums[threadIdx.x+16];
    }
    __syncthreads();

    //8
    if (threadIdx.x<8)
    {
        partialSums[threadIdx.x]+=partialSums[threadIdx.x+8];
    }
    __syncthreads();

    //4
    if (threadIdx.x<4)
    {
        partialSums[threadIdx.x]+=partialSums[threadIdx.x+4];
    }
    __syncthreads();

    if (threadIdx.x==0)
    {
        res = partialSums[0]+partialSums[1]+partialSums[2]+partialSums[3];
        for (LONG64 i=0;i<M;++i)
            toAssign[i]=res;
    }
}

//This function should be called with 1024 threads per block and 1 block
//THIS IS NOT THE MOST EFFICIENT IMPLEMENTATION!!!
template<class ElemType>
__global__ void _reductionSum2(
    const ElemType* data,
    ElemType *sum,
    LONG64 N, 
    bool takeSqrt=false)
{

    __shared__ ElemType partialSums[1024];
    partialSums[threadIdx.x]=0;
    //int id = blockDim.x * blockIdx.x + threadIdx.x;
    LONG64 loadPerThread = N/blockDim.x; 
    for (LONG64 i= threadIdx.x*loadPerThread; i< (threadIdx.x == blockDim.x - 1 ? N : (threadIdx.x+1)*loadPerThread);++i)
        //for (int i= threadIdx.x*loadPerThread; i<(threadIdx.x+1)*loadPerThread;++i)
    {
        partialSums[threadIdx.x]+=(data[i]*data[i]);
    }
    __syncthreads();

    //512
    if (threadIdx.x<512)
    {
        partialSums[threadIdx.x]+=partialSums[threadIdx.x+512];
    }
    __syncthreads();

    //256
    if (threadIdx.x<256)
    {
        partialSums[threadIdx.x]+=partialSums[threadIdx.x+256];
    }
    __syncthreads();

    //128
    if (threadIdx.x<128)
    {
        partialSums[threadIdx.x]+=partialSums[threadIdx.x+128];
    }
    __syncthreads();

    //64
    if (threadIdx.x<64)
    {
        partialSums[threadIdx.x]+=partialSums[threadIdx.x+64];
    }
    __syncthreads();

    //32
    if (threadIdx.x<32)
    {
        partialSums[threadIdx.x]+=partialSums[threadIdx.x+32];
    }
    __syncthreads();

    //16
    if (threadIdx.x<16)
    {
        partialSums[threadIdx.x]+=partialSums[threadIdx.x+16];
    }
    __syncthreads();

    //8
    if (threadIdx.x<8)
    {
        partialSums[threadIdx.x]+=partialSums[threadIdx.x+8];
    }
    __syncthreads();

    //4
    if (threadIdx.x<4)
    {
        partialSums[threadIdx.x]+=partialSums[threadIdx.x+4];
    }
    __syncthreads();

    if (threadIdx.x==0)
    {
        sum[0] = partialSums[0]+partialSums[1]+partialSums[2]+partialSums[3];
        if (takeSqrt)
        {
            if (sizeof(ElemType)==sizeof(float))
                sum[0] = sqrtf(sum[0]);
            else
                sum[0] = sqrt(sum[0]); 
        }
    }
}


//This function should be called with 1024 threads per block and 1 block
//THIS IS NOT THE MOST EFFICIENT IMPLEMENTATION!!!
template<class ElemType>
__global__ void _reductionMatrixNormInf(
    const ElemType* data,
    ElemType *maxAbs,
    LONG64 N)
{

    __shared__ ElemType partialSums[1024];
    partialSums[threadIdx.x]=0;
    //int id = blockDim.x * blockIdx.x + threadIdx.x;
    int loadPerThread = N/blockDim.x; 
    for (int i= threadIdx.x*loadPerThread; i< (threadIdx.x == blockDim.x - 1 ? N : (threadIdx.x+1)*loadPerThread);++i)    
    {
        if (sizeof(ElemType)==sizeof(float))
        {
            partialSums[threadIdx.x]=max(fabsf(data[i]),partialSums[threadIdx.x]);
        }
        else
        {
            partialSums[threadIdx.x]=max(fabs(data[i]),partialSums[threadIdx.x]);
        }
    }
    __syncthreads();

    //512
    if (threadIdx.x<512)
    {
        partialSums[threadIdx.x]=max(partialSums[threadIdx.x+512],partialSums[threadIdx.x]);        
    }
    __syncthreads();

    //256
    if (threadIdx.x<256)
    {
        partialSums[threadIdx.x]=max(partialSums[threadIdx.x+256],partialSums[threadIdx.x]);
    }
    __syncthreads();

    //128
    if (threadIdx.x<128)
    {
        partialSums[threadIdx.x]=max(partialSums[threadIdx.x+128],partialSums[threadIdx.x]);
    }
    __syncthreads();

    //64
    if (threadIdx.x<64)
    {
        partialSums[threadIdx.x]=max(partialSums[threadIdx.x+64],partialSums[threadIdx.x]);
    }
    __syncthreads();

    //32
    if (threadIdx.x<32)
    {
        partialSums[threadIdx.x]=max(partialSums[threadIdx.x+32],partialSums[threadIdx.x]);
    }
    __syncthreads();

    //16
    if (threadIdx.x<16)
    {
        partialSums[threadIdx.x]=max(partialSums[threadIdx.x+16],partialSums[threadIdx.x]);
    }
    __syncthreads();

    //8
    if (threadIdx.x<8)
    {
        partialSums[threadIdx.x]=max(partialSums[threadIdx.x+8],partialSums[threadIdx.x]);
    }
    __syncthreads();

    //4
    if (threadIdx.x<4)
    {
        partialSums[threadIdx.x]=max(partialSums[threadIdx.x+4],partialSums[threadIdx.x]);
    }
    __syncthreads();

    if (threadIdx.x==0)
    {
        maxAbs[0] = max(max(partialSums[0],partialSums[1]),max(partialSums[2],partialSums[3]));
    }
}

//This function should be called with 1024 threads per block and 1 block
//THIS IS NOT THE MOST EFFICIENT IMPLEMENTATION!!!
template<class ElemType>
__global__ void _reductionMatrixNorm0(
    const ElemType* data,
    ElemType *nz,
    LONG64 N)
{

    __shared__ ElemType partialSums[1024];
    partialSums[threadIdx.x]=0;
    //int id = blockDim.x * blockIdx.x + threadIdx.x;
    LONG64 loadPerThread = N/blockDim.x; 
    for (LONG64 i= threadIdx.x*loadPerThread; i< (threadIdx.x == blockDim.x - 1 ? N : (threadIdx.x+1)*loadPerThread);++i)    
    {
        if (data[i]!=0)
            ++partialSums[threadIdx.x];
    }
    __syncthreads();

    //512
    if (threadIdx.x<512)
    {
        partialSums[threadIdx.x]=partialSums[threadIdx.x+512]+partialSums[threadIdx.x];        
    }
    __syncthreads();

    //256
    if (threadIdx.x<256)
    {
        partialSums[threadIdx.x]=partialSums[threadIdx.x+256]+partialSums[threadIdx.x];
    }
    __syncthreads();

    //128
    if (threadIdx.x<128)
    {
        partialSums[threadIdx.x]=partialSums[threadIdx.x+128]+partialSums[threadIdx.x];
    }
    __syncthreads();

    //64
    if (threadIdx.x<64)
    {
        partialSums[threadIdx.x]=partialSums[threadIdx.x+64]+partialSums[threadIdx.x];
    }
    __syncthreads();

    //32
    if (threadIdx.x<32)
    {
        partialSums[threadIdx.x]=partialSums[threadIdx.x+32]+partialSums[threadIdx.x];
    }
    __syncthreads();

    //16
    if (threadIdx.x<16)
    {
        partialSums[threadIdx.x]=partialSums[threadIdx.x+16]+partialSums[threadIdx.x];
    }
    __syncthreads();

    //8
    if (threadIdx.x<8)
    {
        partialSums[threadIdx.x]=partialSums[threadIdx.x+8]+partialSums[threadIdx.x];
    }
    __syncthreads();

    //4
    if (threadIdx.x<4)
    {
        partialSums[threadIdx.x]=partialSums[threadIdx.x+4]+partialSums[threadIdx.x];
    }
    __syncthreads();

    if (threadIdx.x==0)
    {
        nz[0] = partialSums[0]+partialSums[1]+partialSums[2]+partialSums[3];
    }
}


template<class ElemType>
__global__ void _getSparseVectorRepresntationForCSCMatrix(
    const int* m_dRow,
    const int* m_dCol,    
    int* vectArray,    
    const long M,
    const long N)
{
    int i = blockDim.x * blockIdx.x + threadIdx.x;
    if (i>=M)
        return;
    int start = m_dRow[i];
    int end = m_dRow[i+1];
    for (int _i=start;_i<end;++_i)  //_i is index in m_dVal and m_dCol
    {
        int j = m_dCol[_i];
        vectArray[_i] = i*N + j;
    }
}


template<class ElemType>
__global__ void _lrHelper(
    const ElemType* data1,    
    const ElemType* data2,    
    const long N,
    ElemType* d_res)
{
    __shared__ ElemType partialSums1[512];
    __shared__ ElemType partialSums2[512];
    partialSums1[threadIdx.x]=0;
    partialSums2[threadIdx.x]=0;

    //int id = blockDim.x * blockIdx.x + threadIdx.x;
    int loadPerThread = N/blockDim.x;     
    for (int i= threadIdx.x*loadPerThread; i< (threadIdx.x == blockDim.x - 1 ? N : (threadIdx.x+1)*loadPerThread);++i)        
    {
        partialSums1[threadIdx.x]+=(data1[i]*data1[i]);
        partialSums2[threadIdx.x]+=(data2[i]*data2[i]);
    }
    __syncthreads();

    /*
    //512
    if (threadIdx.x<512)
    {
    partialSums1[threadIdx.x]+=partialSums1[threadIdx.x+512];
    partialSums2[threadIdx.x]+=partialSums2[threadIdx.x+512];
    }
    __syncthreads();*/

    //256
    if (threadIdx.x<256)
    {
        partialSums1[threadIdx.x]+=partialSums1[threadIdx.x+256];
        partialSums2[threadIdx.x]+=partialSums2[threadIdx.x+256];        
    }
    __syncthreads();

    //128
    if (threadIdx.x<128)
    {
        partialSums1[threadIdx.x]+=partialSums1[threadIdx.x+128];
        partialSums2[threadIdx.x]+=partialSums2[threadIdx.x+128];        
    }
    __syncthreads();

    //64
    if (threadIdx.x<64)
    {
        partialSums1[threadIdx.x]+=partialSums1[threadIdx.x+64];
        partialSums2[threadIdx.x]+=partialSums2[threadIdx.x+64];        
    }
    __syncthreads();

    //32
    if (threadIdx.x<32)
    {
        partialSums1[threadIdx.x]+=partialSums1[threadIdx.x+32];
        partialSums2[threadIdx.x]+=partialSums2[threadIdx.x+32];        
    }
    __syncthreads();

    //16
    if (threadIdx.x<16)
    {
        partialSums1[threadIdx.x]+=partialSums1[threadIdx.x+16];
        partialSums2[threadIdx.x]+=partialSums2[threadIdx.x+16];        
    }
    __syncthreads();

    //8
    if (threadIdx.x<8)
    {
        partialSums1[threadIdx.x]+=partialSums1[threadIdx.x+8];
        partialSums2[threadIdx.x]+=partialSums2[threadIdx.x+8];        
    }
    __syncthreads();

    //4
    if (threadIdx.x<4)
    {
        partialSums1[threadIdx.x]+=partialSums1[threadIdx.x+4];
        partialSums2[threadIdx.x]+=partialSums2[threadIdx.x+4];        
    }
    __syncthreads();

    if (threadIdx.x==0)
    {        
        ElemType fns1 = partialSums1[0]+partialSums1[1]+partialSums1[2]+partialSums1[3];
        ElemType fns2 = partialSums2[0]+partialSums2[1]+partialSums2[2]+partialSums2[3];
        if (sizeof(ElemType)==sizeof(float))
        {                    
            d_res[0] = max((ElemType)0, d_res[0]/max((ElemType)1.0e-10,sqrtf(fns1))/max((ElemType)1.0e-10,sqrtf(fns2)));            
        }
        else
        {            
            d_res[0] = max((ElemType)0, d_res[0]/max((ElemType)1.0e-10,sqrt(fns1))/max((ElemType)1.0e-10,sqrt(fns2)));              
        }   
    }
}

/*
template<class ElemType>
__global__ void _lrHelper(
ElemType* d_tmp)
{
if (sizeof(ElemType)==sizeof(float))
{
d_tmp[0] = max((ElemType)0, d_tmp[0]/max((ElemType)1.0e-10,sqrtf(d_tmp[1]))/max((ElemType)1.0e-10,sqrtf(d_tmp[2])));            
}
else
{
d_tmp[0] = max((ElemType)0, d_tmp[0]/max((ElemType)1.0e-10,sqrt(d_tmp[1]))/max((ElemType)1.0e-10,sqrt(d_tmp[2])));            
}
}
*/


template<class ElemType>
__global__ void _assignElementProductOfWithShiftNeg(
	ElemType* us,
	const ElemType* a,
	const ElemType* b,
	const int shift,
	const int NTPlusOne,
	const int BS)
{
	LONG64 idx = blockDim.x * blockIdx.x + threadIdx.x;
	LONG64 idy = blockDim.y * blockIdx.y + threadIdx.y;

	if (idx >= NTPlusOne || idy >= BS)
		return;

	if (idx == 0)
	{
		// this is row-0. No need to shift
		us[IDX2C(idx, idy, NTPlusOne)] = a[idy] * b[idy];
	}
	else
	{
		int cs = shift + idx - 1;
		int tmpidy = (idy + cs) % BS;
		us[IDX2C(idx, idy, NTPlusOne)] = a[idy] * b[tmpidy];
	}
}

template<class ElemType>
__global__ void _innerProductWithShiftNeg(
	ElemType* c,
	const ElemType* a,
	const ElemType* b,
	const long N, //a.GetNumRows();
	const long M, //a.GetNumCols();
	const long shift,
	const long NTPlusOne
	)
{
	LONG64 idx = blockDim.x * blockIdx.x + threadIdx.x;
	LONG64 idy = blockDim.y * blockIdx.y + threadIdx.y;

	if (idx >= NTPlusOne || idy >= M)
		return;

	ElemType sum = 0;
	long index_a = 0;
	long index_b = 0;
	long col_a = 0;
	long col_b = 0;
	if (idx == 0)
	{
		// this is row 0. No need to shift
		// the product of a(:,idy) dot b(:,idy)
		col_a = idy;
		for (long i = 0; i < N; ++i)
		{
			index_a = IDX2C(i, col_a, N);
			sum += a[index_a] * b[index_a];
		}
	}
	else
	{
		int cs = shift + idx - 1;
		col_a = idy;
		col_b = (idy + cs) % M;
		for (int i = 0; i < N; ++i)
		{
			index_a = IDX2C(i, col_a, N);
			index_b = IDX2C(i, col_b, N);
			sum += a[index_a] * b[index_b];
		}
	}
	c[IDX2C(idx, idy, NTPlusOne)] = sum;

}

template<class ElemType>
__global__ void _getARowByIndex(
	ElemType* us,
	const ElemType* a,
	const int O, // a's rows
	const int P, // a's cols
	const int m // the m-th row of a
	)
{
	LONG64 id = blockDim.x * blockIdx.x + threadIdx.x;
	if (id >= P)
		return;
	//	us[id] = a[id] * b[id];
	us[id] = a[IDX2C(m, id, O)];
}


template<class ElemType>
__global__ void _conductRowElementMultiplyWithShift(
	ElemType* us,
	const ElemType* a,
	const ElemType* b,
	const int O, // b's rows
	const int P, // b's cols
	const int shift,
	const bool isafixed)
{
	LONG64 idx = blockDim.x * blockIdx.x + threadIdx.x;
	LONG64 idy = blockDim.y * blockIdx.y + threadIdx.y;

	if (idx >= O || idy >= P)
		return;

	int tmpidy = (idy + shift) % P;
	if (isafixed)
	{
		// we fix a, and shift b
		us[IDX2C(idx, idy, O)] = a[idy] * b[IDX2C(idx, tmpidy, O)];
	}
	else
	{
		// we fix b, but shift a
		us[IDX2C(idx, idy, O)] = a[tmpidy] * b[IDX2C(idx, idy, O)];
	}

}

template<class ElemType>
__global__ void _assignElementProductOfWithShift(
	ElemType* us,
	const ElemType* a,
	const ElemType* b,
	const int shift,
	const LONG64 N)
{
	LONG64 id = blockDim.x * blockIdx.x + threadIdx.x;
	if (id >= N)
		return;

	int tmpidb = (id + shift) % N;
	us[id] = a[id] * b[tmpidb];
}


/// minus 1 at a specific position
template<class ElemType>
__global__ void _minusOneAt(
    ElemType *c,
    LONG64 position, 
    LONG64 N)
{
    LONG64 id = blockDim.x * blockIdx.x + threadIdx.x;
    if (id >= N)
        return;
    if (id == position)
        c[id] = c[id] - 1.0; 
}


/// the kernel function for RCRF  backward computation
/// assume a column slice of input and output
template<class ElemType>
__global__ void _rcrfBackwardCompute(
    const size_t iNumPos,
    const ElemType* galpha,   /// column slice at current time t
    ElemType* gbeta,          /// column slices with [row, 2] at current time t for [
    const ElemType* gpair_scores,
    const size_t iNumLab, const int shift)
{
    int id = blockDim.x * blockIdx.x + threadIdx.x;

    extern __shared__ double sh_alpha_and_beta[]; /// intersting, has to use [], instead of *
    /// need bye size = (iNumPos * iNumLab * 2 + iNumLab * iNumLab) * sizeof(ElemType)

    ElemType * alpha = (ElemType*)(sh_alpha_and_beta);
    ElemType * pair_scores = alpha + iNumPos * iNumLab;
    ElemType * beta = alpha + iNumPos * iNumLab + iNumLab * iNumLab;

    if (id < 0 || id >= iNumLab)
        return;

    /// copy global memory to shared memory to save time
    for (int t = iNumPos - 1; t >= 0; t--)
    {
        alpha[IDX2C(id, t, iNumLab)] = galpha[IDX2C(id, t, iNumLab)];
    }

    for (int j = 0; j < iNumLab; j++)
        pair_scores[IDX2C(id, j, iNumLab)] = gpair_scores[IDX2C(id, j, iNumLab)];

    __syncthreads();

    for (int t = iNumPos - 1; t >= 0; t--)
    {
        ElemType fSum;
        ElemType fTmp = LZERO;
        if (t == iNumPos - 1)
        {
            fSum = LZERO;
            for (int j = 0; j < iNumLab; j++)
            {
                fSum = logadd(fSum, alpha[IDX2C(j, t, iNumLab)]);
            }

            fTmp = alpha[IDX2C(id, t, iNumLab)] - fSum;
        }
        else
        {
            for (int j = 0; j < iNumLab; j++)
            {
                fSum = LZERO;
                for (int m = 0; m < iNumLab; m++)
                {
                    fSum = logadd(fSum, alpha[IDX2C(m, t, iNumLab)] + pair_scores[IDX2C(j, m, iNumLab)]);
                }

                fTmp = logadd(fTmp, beta[IDX2C(j, t + 1, iNumLab)] + alpha[IDX2C(id, t, iNumLab)] + pair_scores[IDX2C(j, id, iNumLab)] - fSum);
            }
        }

        beta[IDX2C(id, t, iNumLab)] = fTmp;
        __syncthreads();
    }

    /// copy from shared memory to global memory to pass values
    for (int t = iNumPos - 1; t >= 0; t--)
    {
        gbeta[IDX2C(id, t, iNumLab)] = beta[IDX2C(id, t, iNumLab)];
    }
    //    __syncthreads();
}

/// the kernel function for RCRF  backward computation
/// assume a column slice of input and output
template<class ElemType>
__global__ void _rcrfBackwardCompute(
    const size_t t, /// time position 
    const size_t iNumPos,
    const ElemType* galpha,   /// column slice at current time t
    ElemType* gbeta,          /// column slices with [row, 2] at current time t for [
    const ElemType* gzeta,          /// column slices with [row, 2] at current time t for [
    const ElemType* gpair_scores,   /// column slice at current time t
    const size_t iNumLab, const int shift)
{
    int id = blockDim.x * blockIdx.x + threadIdx.x;

    extern __shared__ double sh_alpha_and_beta[]; /// intersting, has to use [], instead of *
    /// need bye size = (iNumPos * iNumLab * 2 + iNumLab * iNumLab) * sizeof(ElemType)

    ElemType * alpha = (ElemType*)(sh_alpha_and_beta);
    ElemType * beta_t1 = (ElemType*)(alpha + iNumLab);
    ElemType * zeta = (ElemType*)(beta_t1 + iNumLab);
    ElemType pair_scores[1024];

    if (id < 0 || id >= iNumLab)
        return;

    /// copy global memory to shared memory to save time
    alpha[id] = galpha[IDX2C(id, t, iNumLab)];
    if (t < iNumPos - 1)
        beta_t1[id] = gbeta[IDX2C(id, t + 1, iNumLab)];
    zeta[id] = gzeta[id];

    __syncthreads();

    for (int j = 0; j < iNumLab; j++)
        pair_scores[j] = gpair_scores[IDX2C(j, id, iNumLab)];

    ElemType fTmp = LZERO;
    if (t == iNumPos - 1)
    {
        fTmp = alpha[id] - zeta[id];
    }
    else
    {
        for (int j = 0; j < iNumLab; j++)
        {
            fTmp = logadd(fTmp, beta_t1[j] + alpha[id] + pair_scores[j] - zeta[j]);
        }
    }

    gbeta[IDX2C(id, t, iNumLab)] = fTmp;

}

/// $\zeta_t(j) = {\sum_k exp(\delta_{t-1}(k) + a_{kj}(t))}$.
template<class ElemType>
__global__ void _rcrfBackwardComputeZeta(
    const size_t t, /// time position 
    const size_t iNumPos,
    const ElemType* galpha,   /// column slice at current time t
    ElemType* gzeta,          /// column slices with [row, 2] at current time t for [
    const ElemType* gpair_scores,
    const size_t iNumLab, const int shift)
{
    int id = blockDim.x * blockIdx.x + threadIdx.x;

    extern __shared__ double sh_alpha_and_beta[]; /// intersting, has to use [], instead of *
    /// need bye size = (iNumPos * iNumLab * 2 + iNumLab * iNumLab) * sizeof(ElemType)

    ElemType * alpha = (ElemType*)(sh_alpha_and_beta);
    ElemType pair_scores[1024];

    if (id < 0 || id >= iNumLab)
        return;

    /// copy global memory to shared memory to save time
    alpha[id] = galpha[IDX2C(id, t, iNumLab)];

    __syncthreads();

    for (int j = 0; j < iNumLab; j++)
        pair_scores[j] = gpair_scores[IDX2C(id, j, iNumLab)];

    ElemType fSum = LZERO;
    for (int m = 0; m < iNumLab; m++)
    {
        if (t == iNumPos - 1)
            fSum = logadd(fSum, alpha[IDX2C(m, 0, iNumLab)]);
        else
            fSum = logadd(fSum, alpha[IDX2C(m, 0, iNumLab)] + pair_scores[m]);
    }

    gzeta[id] = fSum;

}

/// $\zeta_t(j) = {\sum_k exp(\delta_{t-1}(k) + a_{kj}(t))}$.
template<class ElemType>
__global__ void _rcrfTransGrdComputeZeta(
    const int t, /// time position 
    const size_t iNumPos,
    const ElemType* galpha,   /// column slice at current time t
    ElemType* gzeta,          /// column slices with [row, 2] at current time t for [
    const ElemType* gpair_scores,
    const size_t iNumLab,
    const size_t start_lbl,
    const int shift)
{
    int id = blockDim.x * blockIdx.x + threadIdx.x;

    extern __shared__ double sh_alpha_and_beta[]; /// intersting, has to use [], instead of *
    /// need bye size = (iNumPos * iNumLab * 2 + iNumLab * iNumLab) * sizeof(ElemType)

    ElemType * alpha = (ElemType*)(sh_alpha_and_beta);
    ElemType pair_scores[1024];

    if (id < 0 || id >= iNumLab)
        return;

    /// copy global memory to shared memory to save time
    if (t >= 0)
        alpha[id] = galpha[IDX2C(id, t, iNumLab)];

    __syncthreads();

    for (int j = 0; j < iNumLab; j++)
        pair_scores[j] = gpair_scores[IDX2C(id, j, iNumLab)];

    ElemType fSum = LZERO;
    ElemType fTmp;
    for (int m = 0; m < iNumLab; m++)
    {
        if (t < 0)
        {
            if (m == start_lbl)
                fTmp = 0;
            else fTmp = LZERO;
        }
        else
            fTmp = alpha[m];

        fSum = logadd(fSum, pair_scores[m] + fTmp);
    }

    gzeta[id] = fSum;

}

template<class ElemType>
__global__ void _rcrfTransGrdCompute(
    int t,
    const size_t start_lbl,
    const ElemType*   galpha,
    const ElemType* gbeta,
    const ElemType* gzeta,
    const ElemType* gpair_scores,
    const ElemType * lbls,
    ElemType* grd,
    const size_t iNumPos,
    const size_t iNumLab,
    const int shift)
{
    int id = blockDim.x * blockIdx.x + threadIdx.x;

    extern __shared__ double sh_alpha_and_beta[]; /// intersting, has to use [], instead of *
    /// need bye size = (iNumPos * iNumLab * 2 + iNumLab * iNumLab) * sizeof(ElemType)

    ElemType * alpha = (ElemType*)(sh_alpha_and_beta);
    ElemType * beta = (ElemType*)(alpha + iNumLab);
    ElemType * zeta = (ElemType*)(beta + iNumLab);
    ElemType pair_scores[1024];

    if (id < 0 || id >= iNumLab)
        return;

    /// copy global memory to shared memory to save time
    if (t > 0)
        alpha[id] = galpha[IDX2C(id, t - 1, iNumLab)];
    beta[id] = gbeta[IDX2C(id, t, iNumLab)];
    zeta[id] = gzeta[id];

    __syncthreads();

    for (int j = 0; j < iNumLab; j++)
        pair_scores[j] = gpair_scores[IDX2C(j, id, iNumLab)];

    ElemType fTmp;
    ElemType fTmp2;
    for (int j = 0; j < iNumLab; j++){
        if (t == 0)
        {
            if (id == start_lbl)
                fTmp = 0;
            else
                fTmp = LZERO;
        }
        else
            fTmp = alpha[id];

        fTmp2 = fTmp + pair_scores[j] - zeta[j];
        assert(fTmp2 <= 0.0);
        fTmp2 += beta[j];

        fTmp = exp(fTmp2);
        grd[IDX2C(j, id, iNumLab)] += fTmp;
    }

    if ((t == 0 && id == start_lbl) || (t > 0 && t < iNumPos && lbls[IDX2C(id, t - 1, iNumLab)] != 0))
    {
        for (int ik = 0; ik < iNumLab; ik++)
        {
            if (lbls[IDX2C(ik, t, iNumLab)] != 0)
                grd[IDX2C(ik, id, iNumLab)] -= 1.0;
        }
    }

};

template<class ElemType>
__global__ void _reductionLogAddSum(
    const ElemType* data,
    ElemType *sum,
    const size_t sum_size,
    LONG64 N)
{

    __shared__ ElemType partialLogAddSum[threadsPerBlock];

    int id = blockDim.x * blockIdx.x + threadIdx.x;
    int tid = threadIdx.x;

    if (id < N)
        partialLogAddSum[tid] = data[id];
    else
        partialLogAddSum[tid] = LZERO;

    __syncthreads();

    /// do reduction on the shared memory
    size_t start_width = ceil((N + 0.0) / 2.0);
    for (size_t s = start_width; s > 0; s >>= 1)
    {
        ElemType lSum = LZERO;
        if (tid < s){
            lSum = logadd(partialLogAddSum[tid], partialLogAddSum[tid + s]);
            partialLogAddSum[tid] = lSum;
        }
    }
    __syncthreads();


    if (tid == 0)
        sum[0] = partialLogAddSum[0];
}


#endif // !CPUONLY