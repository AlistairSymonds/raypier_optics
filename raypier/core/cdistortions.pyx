
cdef extern from "math.h":
    double M_PI
    double sqrt(double) nogil
    double atan2 (double y, double x ) nogil
    double pow(double x, double y) nogil
    double fabs(double) nogil
    double cos(double) nogil
    double sin(double) nogil
    double acos(double) nogil
    double floor(double) nogil
    int isnan(double) nogil
    int abs(int) nogil

cdef extern from "float.h":
    double DBL_MAX
    
from libc.stdlib cimport malloc, free, realloc

cdef double INF=(DBL_MAX+DBL_MAX)
cdef double NAN=float("NaN")

from .ctracer cimport Face, sep_, \
        vector_t, ray_t, FaceList, subvv_, dotprod_, mag_sq_, norm_,\
            addvv_, multvs_, mag_, transform_t, Transform, transform_c,\
                rotate_c, Shape, Distortion
                
cimport cython
cimport numpy as np_
import numpy as np
                
                
cdef class SimpleTestZernikeJ7(Distortion):
    """Implement one low-order Zernike poly for testing purposes.
    """
    cdef:
        public double unit_radius
        public double amplitude
        
    def __cinit__(self, **kwds):
        self.unit_radius = kwds.get("unit_radius", 1.0)
        self.amplitude = kwds.get("amplitude", 1.0)
        
    cdef double z_offset_c(self, double x, double y) nogil:
#         cdef:
#             double rho, Z
            
        x /= self.unit_radius
        y /= self.unit_radius
        #rho = sqrt(x*x + y*y)
        #theta = atan2(y, x)
        Z = sqrt(8.0)*(3*(x*x + y*y) - 2)*y
        return Z * self.amplitude
    
    cdef vector_t z_offset_and_gradient_c(self, double x, double y) nogil:
        """The z-axis surface sag is returned as the z-component 
        of the output vector. The x- and y-components of the surface
        gradient are placed in the x- and y- components of vector.
        I.e. the returned vector is
            (dz(x,y)/dx, dz(x,y)/dy, z(x,y))
        """
        cdef:
            double rho, theta, Z, root8=sqrt(8)*self.amplitude, R=self.unit_radius
            vector_t p
            
        x /= R
        y /= R
            
        #rho = sqrt(x*x + y*y)
        #theta = atan2(y, x)
            
        p.x = root8 * 6*x*y /R #root8*(6*y + (3*rho*rho-2)/y)*x
        p.y = root8 * (3*x*x + 9*y*y -2)/R#root8*(6*y*y + 3*rho*rho - 2)
        p.z = root8*(3*(x*x + y*y) - 2)*y 
        return p
    
    
cdef packed struct zernike_coef_t:
    int j
    int n
    int m
    int k
    double value
    
    
cdef struct zer_nmk:
    int n
    int m
    int k
    
    
jnm_map = [(0,0,0)]
    

cdef zer_nmk eval_nmk_c(int j):
    ### Figure out n,m indices from a given j-index
    cdef:
        zer_nmk out
        int n, m, k, next_j, half_n
        
    if j<0:
        raise ValueError("J must be non-negative")
        
    if j >= len(jnm_map):
        n,m,k = jnm_map[-1]
        while True:
            while m<n:
                m += 2
                next_j = (n*(n+2) + m)//2
                half_n = int(floor(n/2.))
                k = half_n*(half_n + 1) + abs(m)
                jnm_map.append( (n,m,k) )
                if next_j == j:
                    out.n = n
                    out.m = m
                    out.k = k
                    return out
                elif next_j > j:
                    raise ValueError("Something went wrong here! Missed j value.")
            n += 1
            m = -2 - n
        
    nmk = jnm_map[j]
    out.n = nmk[0]
    out.m = nmk[1]
    out.k = nmk[2]
    return out


def eval_nmk(int j):
    cdef zer_nmk out
    out = eval_nmk_c(j)
    return (out.n, out.m, out.k)


@cython.boundscheck(False)  # Deactivate bounds checking
@cython.wraparound(False)   # Deactivate negative indexing.
@cython.nonecheck(False)
@cython.cdivision(True)
cdef double zernike_R_c(double r, int k, int n, int m, double[:] workspace) nogil:
    cdef:
        int kA, kB, kC, nA, nB, nC, mA, mB, mC , half_n
        double val
        
    if n < m:
        return 0.0
    
    val = workspace[k]
    if isnan(val):
        nA = n-1
        mA = abs(m-1)
        half_n = nA/2
        kA = half_n*(half_n+1) + abs(mA)#(nA*(nA+2) + mA)//2
        nB = nA
        mB = m+1
        kB = half_n*(half_n+1) + abs(mB) #(nB*(nB+2) + mB)//2
        nC = n-2
        mC = m
        kC = (half_n-1)*half_n + abs(mC) #(nC*(nC+2) + mC)//2
        val = r*(zernike_R_c(r, kA, nA, mA, workspace) + zernike_R_c(r, kB, nB, mB, workspace))
        val -= zernike_R_c(r, kC, nC, mC, workspace)
        workspace[k] = val
        return val
    else:
        return val

    
def zernike_R(double r, int k, int n, int m, double[:] workspace):
    return zernike_R_c(r,k,n,m, workspace)
    
    
@cython.boundscheck(False)  # Deactivate bounds checking
@cython.wraparound(False)   # Deactivate negative indexing.
@cython.nonecheck(False)
@cython.cdivision(True)
cdef double zernike_Rprime_c(double r, int k, int n, int m, double[:] workspace, double[:] workspace2) nogil:
    cdef:
        int kA, kB, kC, nA, nB, nC, mA, mB, mC, half_n
        double val
        
    if n < m:
        return 0.0
    
    val = workspace2[k]
    if isnan(val):
        nA = n-1
        mA = abs(m-1)
        half_n = nA/2
        kA = half_n*(half_n+1) + abs(mA)
        nB = nA
        mB = m+1
        kB = half_n*(half_n+1) + abs(mB)
        nC = n-2
        mC = m
        kC = (half_n-1)*half_n + abs(mC)
        val = zernike_R_c(r, kA, nA, mA, workspace) + zernike_R_c(r, kB, nB, mB, workspace)
        val += r*( zernike_Rprime_c(r, kA, nA, mA, workspace, workspace2) + \
                   zernike_Rprime_c(r, kB, nB, mB, workspace, workspace2) )
        val -= zernike_Rprime_c(r, kC, nC, mC, workspace, workspace2)
        workspace2[k] = val
        return val
    else:
        return val
    
    
def zernike_Rprime(double r, int k, int n, int m, double[:] workspace, double[:] workspace2):
    return zernike_Rprime_c(r,k,n,m,workspace, workspace2)

    
                
cdef class ZernikeDistortion(Distortion):
    cdef:
        public double unit_radius
        
        public int n_coefs, j_max, k_max
        
        zernike_coef_t[:] coefs
        double[:] workspace
        double[:] workspace2
         
    def __cinit__(self, **coefs):
        cdef:
            int n,m,i, j,size, j_max, k_max
            list clist
            zer_nmk nmk
            double v
            
        clist = [(int(k[1:]), float(v)) for k,v in coefs if k.startswith("j")]
        j_max = max(a[0] for a in clist)
        k_max = eval_nmk(j_max)[2]
        self.j_max = j_max
        self.k_max = k_max
        size = len(clist)
        self.coefs = <zernike_coef_t[:size]>malloc(size*sizeof(zernike_coef_t))
        self.n_coefs = size
        for i in range(size):
            j,v = clist[i]
            self.coefs[i].j = j
            nmk = eval_nmk_c(j)
            self.coefs[i].n = nmk.n
            self.coefs[i].m = nmk.m
            self.coefs[i].k = nmk.k
            self.coefs[i].value = v
            
        self.workspace = <double[:k_max]>malloc(k_max*sizeof(double))
        self.workspace2 = <double[:k_max]>malloc(k_max*sizeof(double))
            
    def __dealloc__(self):
        free(&(self.coefs[0]))
        free(&(self.workspace[0]))
        free(&(self.workspace2[0]))
        
    def __getitem__(self, int idx):
        if idx >= self.n_coefs:
            raise IndexError(f"Index {idx} greater than number of coeffs ({self.n_coefs}).")
        
    def __len__(self):
        return self.n_coefs
        
    @cython.boundscheck(False)  # Deactivate bounds checking
    @cython.wraparound(False)   # Deactivate negative indexing.
    @cython.nonecheck(False)
    @cython.cdivision(True)
    cdef double z_offset_c(self, double x, double y) nogil:
        cdef:
            double r, theta, Z=0.0, N, PH
            int i
            zernike_coef_t coef
            double[:] workspace
            
        x /= self.unit_radius
        y /= self.unit_radius
        r = sqrt(x*x + y*y)
        theta = atan2(y, x)
        
        workspace = self.workspace
        for i in range(self.j_max):
            workspace[i] = NAN
        workspace[0] = 1.0 #initialise the R_0_0 term
        
        for i in range(self.n_coefs):
            coef = self.coefs[i]
            
            if coef.m==0:
                N = sqrt(coef.n+1)
            else:
                N = sqrt(2*(coef.n+1))
                
            if coef.m >= 0:
                PH = cos(coef.m*theta)
            else:
                PH = -sin(coef.m*theta)
            
            Z += N * zernike_R_c(r, coef.k, coef.n, abs(coef.m), workspace) * PH * coef.value
        
        return Z
        
    @cython.boundscheck(False)  # Deactivate bounds checking
    @cython.wraparound(False)   # Deactivate negative indexing.
    @cython.nonecheck(False)
    @cython.cdivision(True)
    cdef vector_t z_offset_and_gradient_c(self, double x, double y) nogil:
        """The z-axis surface sag is returned as the z-component 
        of the output vector. The x- and y-components of the surface
        gradient are placed in the x- and y- components of vector.
        I.e. the returned vector is
            (dz(x,y)/dx, dz(x,y)/dy, z(x,y))
        """
        cdef:
            double r, theta, N, PH, Rprime
            int i
            zernike_coef_t coef
            double[:] workspace
            double[:] workspace2
            vector_t Z
            
        x /= self.unit_radius
        y /= self.unit_radius
        r = sqrt(x*x + y*y)
        theta = atan2(y, x)
        
        workspace = self.workspace
        workspace2 = self.workspace2
        for i in range(self.k_max):
            workspace[i] = NAN
            workspace2[i] = NAN
        workspace[0] = 1.0 #initialise the R_0_0 term
        workspace2[0] = 0.0 #Gradient of 0th term is zero
        
        Z.x = 0.0
        Z.y = 0.0
        Z.z = 0.0
        
        for i in range(self.n_coefs):
            coef = self.coefs[i]
            
            if coef.m==0:
                N = sqrt(coef.n+1)
            else:
                N = sqrt(2*(coef.n+1))
                
            if coef.m >= 0:
                PH = cos(coef.m*theta)
            else:
                PH = -sin(coef.m*theta)
            
            Z.z += N * zernike_R_c(r, coef.k, coef.n, abs(coef.m), workspace) * PH * coef.value
            Rprime = zernike_Rprime_c(r, coef.k, coef.n, abs(coef.m), workspace, workspace2)
            ### Now eval partial derivatives
        
        return Z
        