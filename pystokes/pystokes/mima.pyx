cimport cython
from libc.math cimport sqrt, exp, pow, erfc, sin, cos
from cython.parallel import prange
import numpy as np
cimport numpy as np
cdef double PI = 3.14159265359

cdef extern from "complex.h" nogil:
    double complex cexp(double complex x)

@cython.boundscheck(False)
@cython.cdivision(True)
@cython.nonecheck(False)
@cython.wraparound(False)
cdef class Flow:
    def __init__(self, a_, Np_, Lx_, Ly_, Lz_, Nx_, Ny_, Nz_ ):
        self.a = a_
        self.Np = Np_
        self.Lx = Lx_
        self.Ly = Ly_
        self.Lz = Lz_
        self.Nx = Nx_
        self.Ny = Ny_
        self.Nz = Nz_

        self.facx = 2*PI/Nx_
        self.facy = 2*PI/Ny_
        self.facz = 2*PI/Nz_
        
        self.fx0 = np.zeros((Nx_, Ny_, Nz_), dtype=np.float) 
        self.fk0 = np.zeros((Nx_, Ny_, Nz_), dtype=np.complex128)
        self.fkx = np.empty((Nx_, Ny_, Nz_), dtype=np.complex128) 
        self.fky = np.empty((Nx_, Ny_, Nz_), dtype=np.complex128)
        self.fkz = np.empty((Nx_, Ny_, Nz_), dtype=np.complex128)
        self.vkx = np.empty((Nx_, Ny_, Nz_), dtype=np.complex128) 
        self.vky = np.empty((Nx_, Ny_, Nz_), dtype=np.complex128)
        self.vkz = np.empty((Nx_, Ny_, Nz_), dtype=np.complex128)
       

    cpdef stokesletV(self, np.ndarray v, double [:] r, double [:] F, double sigma=3, int NN=20):
        cdef:
            int i, nx, ny, nz , x, y, z, Nx, Ny, Nz, Np, jx, jy, jz
            double arg, facx, facy, facz, kx, ky, kz
            double kdotdr, a2, k2
        Nx, Ny, Nz = self.Nx, self.Ny, self.Nz 
        facx, facy, facz = self.facx, self.facy, self.facz
        Np, a2 = self.Np, self.a*self.a/6.0
        
        self.fourierFk(sigma, NN)  # construct the fk0 
            
        cdef complex [:, :, :] fk0 = self.fk0
        cdef complex [:, :, :] fkx = self.fkx
        cdef complex [:, :, :] fky = self.fky
        cdef complex [:, :, :] fkz = self.fkz

        for jz in prange(Nz, nogil=True): 
            for jy in range(Ny): 
                for jx in range(Nx): 
                    for i in range(Np):
                        i = i*3
                        kx = jx*facx if jx <= Nx / 2 else (-Nx+jx)*facx
                        ky = jy*facy if jy <= Ny / 2 else (-Ny+jy)*facy
                        kz = jz*facz if jz <= Nz / 2 else (-Nz+jz)*facz
                        kdotdr = kx*(r[i]-Nx/2) + ky*(r[i+1]-Ny/2) + kz*(r[i+2]-Nz/2)
                        k2 = kx*kx + ky*ky + kz*kz
                        
                        fkx[jy, jx, jz] += fk0[jy, jx, jz]*F[i]     *cexp(1j*kdotdr)*(1-a2*k2)
                        fky[jy, jx, jz] += fk0[jy, jx, jz]*F[i+1]  *cexp(1j*kdotdr)*(1-a2*k2)
                        fkz[jy, jx, jz] += fk0[jy, jx, jz]*F[i+2]*cexp(1j*kdotdr)*(1-a2*k2)
        
        self.solve( v, np.concatenate(( self.fkx.ravel(), self.fky.ravel(), self.fkz.ravel() )) )
        return


    cpdef rotletV(self, np.ndarray v, double [:] r, double [:] T, double sigma=3, int NN=20):
        cdef:
            int i, nx, ny, nz , x, y, z, Nx, Ny, Nz, Np, jx, jy, jz
            double arg, facx, facy, facz, kx, ky, kz
            double kdotdr, k2
        Nx, Ny, Nz = self.Nx, self.Ny, self.Nz 
        facx, facy, facz = self.facx, self.facy, self.facz
        Np = self.Np
        
        self.fourierFk(sigma, NN)  # construct the fk0 
            
        cdef complex [:, :, :] fk0 = self.fk0
        cdef complex [:, :, :] fkx = self.fkx
        cdef complex [:, :, :] fky = self.fky
        cdef complex [:, :, :] fkz = self.fkz

        for jz in prange(Nz, nogil=True): 
            for jy in range(Ny): 
                for jx in range(Nx): 
                    for i in range(Np):
                        i = i*3
                        kx = jx*facx if jx <= Nx / 2 else (-Nx+jx)*facx
                        ky = jy*facy if jy <= Ny / 2 else (-Ny+jy)*facy
                        kz = jz*facz if jz <= Nz / 2 else (-Nz+jz)*facz
                        kdotdr = kx*(r[i]-Nx/2) + ky*(r[i+1]-Ny/2) + kz*(r[i+2]-Nz/2)
                        
                        fkx[jy, jx, jz] += fk0[jy, jx, jz]*( T[i+1]  *kz - T[i+2]*ky  )*cexp(1j*kdotdr)
                        fky[jy, jx, jz] += fk0[jy, jx, jz]*( T[i+2]*kx - T[i]     *kz  )*cexp(1j*kdotdr)
                        fkz[jy, jx, jz] += fk0[jy, jx, jz]*( T[i]     *ky - T[i+1]  *kx  )*cexp(1j*kdotdr)
        
        self.solve( v, np.concatenate(( self.fkx.ravel(), self.fky.ravel(), self.fkz.ravel() )) )
        return


    cpdef stressletV(self, np.ndarray v, double [:] r, double [:] S, double sigma=3, int NN=20):
        cdef:
            int i, nx, ny, nz , x, y, z, Nx, Ny, Nz, Np, jx, jy, jz
            double arg, facx, facy, facz, kx, ky, kz, skx, sky, skz
            double kdotdr, a2, k2
        Nx, Ny, Nz = self.Nx, self.Ny, self.Nz 
        facx, facy, facz = self.facx, self.facy, self.facz
        Np, a2 = self.Np, self.a*self.a/10
        
        self.fourierFk(sigma, NN)  # construct the fk0 
            
        cdef complex [:, :, :] fk0 = self.fk0
        cdef complex [:, :, :] fkx = self.fkx
        cdef complex [:, :, :] fky = self.fky
        cdef complex [:, :, :] fkz = self.fkz

        for jz in prange(Nz, nogil=True): 
            for jy in range(Ny): 
                for jx in range(Nx): 
                    for i in range(Np):
                        i = i*3
                        kx = jx*facx if jx <= Nx / 2 else (-Nx+jx)*facx
                        ky = jy*facy if jy <= Ny / 2 else (-Ny+jy)*facy
                        kz = jz*facz if jz <= Nz / 2 else (-Nz+jz)*facz
                        kdotdr = kx*(r[i]-Nx/2) + ky*(r[i+1]-Ny/2) + kz*(r[i+2]-Nz/2)
                        k2 = kx*kx + ky*ky + kz*kz
                        skx = S[i]     *kx  + S[i+2]*ky + S[i+3*Np]     *kz     # sxx, syy, sxy, sxz, syz
                        sky = S[i+2]*kx  + S[i+1]  *ky   + S[i+4*Np]   *kz
                        skz = S[i+3*Np]*kx  + S[i+4*Np]*ky - (S[i]+S[i+1])*kz
                        
                        fkx[jy, jx, jz] += -1j*fk0[jy, jx, jz]*skx*cexp(1j*kdotdr)*(1-a2*k2)
                        fky[jy, jx, jz] += -1j*fk0[jy, jx, jz]*sky*cexp(1j*kdotdr)*(1-a2*k2)
                        fkz[jy, jx, jz] += -1j*fk0[jy, jx, jz]*skz*cexp(1j*kdotdr)*(1-a2*k2)
        self.solve( v, np.concatenate(( self.fkx.ravel(), self.fky.ravel(), self.fkz.ravel() )) )
        return


    cpdef potDipoleV(self, np.ndarray v, double [:] r, double [:] D, double sigma=3, int NN=20):
        cdef:
            int i, nx, ny, nz , x, y, z, Nx, Ny, Nz, Np, jx, jy, jz
            double arg, facx, facy, facz, kx, ky, kz
            double kdotdr, a2, k2
        Nx, Ny, Nz = self.Nx, self.Ny, self.Nz 
        facx, facy, facz = self.facx, self.facy, self.facz
        Np = self.Np
        
        self.fourierFk(sigma, NN)  # construct the fk0 
            
        cdef complex [:, :, :] fk0 = self.fk0
        cdef complex [:, :, :] fkx = self.fkx
        cdef complex [:, :, :] fky = self.fky
        cdef complex [:, :, :] fkz = self.fkz

        for jz in prange(Nz, nogil=True): 
            for jy in range(Ny): 
                for jx in range(Nx): 
                    for i in range(Np):
                        i = i*3
                        kx = jx*facx if jx <= Nx / 2 else (-Nx+jx)*facx
                        ky = jy*facy if jy <= Ny / 2 else (-Ny+jy)*facy
                        kz = jz*facz if jz <= Nz / 2 else (-Nz+jz)*facz
                        kdotdr = kx*(r[i]-Nx/2) + ky*(r[i+1]-Ny/2) + kz*(r[i+2]-Nz/2)
                        
                        fkx[jy, jx, jz] += fk0[jy, jx, jz]*D[i]     *cexp(1j*kdotdr)
                        fky[jy, jx, jz] += fk0[jy, jx, jz]*D[i+1]  *cexp(1j*kdotdr)
                        fkz[jy, jx, jz] += fk0[jy, jx, jz]*D[i+2]*cexp(1j*kdotdr)
        
        self.solve( v, np.concatenate(( self.fkx.ravel(), self.fky.ravel(), self.fkz.ravel() )) )
        return
    
    
    cpdef septletV(self, np.ndarray v, double [:] r, double [:] G, double sigma=3, int NN=20):
        cdef:
            int i, nx, ny, nz , x, y, z, Nx, Ny, Nz, Np, jx, jy, jz
            double arg, facx, facy, facz, kx, ky, kz, grrr, grrx, grry, grrz, gxxx, gyyy, gxxy, gxxz, gxyy, gxyz, gyyz
            double kdotdr, a2, k2
        Nx, Ny, Nz = self.Nx, self.Ny, self.Nz 
        facx, facy, facz = self.facx, self.facy, self.facz
        Np, a2 = self.Np, self.a*self.a/14
        
        self.fourierFk(sigma, NN)  # construct the fk0 
            
        cdef complex [:, :, :] fk0 = self.fk0
        cdef complex [:, :, :] fkx = self.fkx
        cdef complex [:, :, :] fky = self.fky
        cdef complex [:, :, :] fkz = self.fkz
                
        for i in prange(Np, nogil=True):
            gxxx = G[7*i]
            gyyy = G[7*i+1]
            gxxy = G[7*i+2]
            gxxz = G[7*i+3*Np]
            gxyy = G[7*i+4*Np]
            gxyz = G[7*i+5*Np]
            gyyz = G[7*i+6*Np]

        for jz in prange(Nz, nogil=True): 
            for jy in range(Ny): 
                for jx in range(Nx): 
                    for i in range(Np):
                        kx = jx*facx if jx <= Nx / 2 else (-Nx+jx)*facx
                        ky = jy*facy if jy <= Ny / 2 else (-Ny+jy)*facy
                        kz = jz*facz if jz <= Nz / 2 else (-Nz+jz)*facz
                        kdotdr = kx*(r[i]-Nx/2) + ky*(r[i+1]-Ny/2) + kz*(r[i+2]-Nz/2)
                        k2 = kx*kx + ky*ky + kz*kz
                        
                        grrr = gxxx*kx*(kx*kx-3*kz*kz) + 3*gxxy*ky*(kx*kx-kz*kz) + gxxz*kz*(3*kx*kx-kz*kz) +\
                                   3*gxyy*kx*(ky*ky-kz*kz) + 6*gxyz*kx*ky*kz + gyyy*ky*(ky*ky-3*kz*kz) +  gyyz*kz*(3*ky*ky-kz*kz) 
                        grrx = gxxx*(kx*kx-kz*kz) + gxyy*(ky*ky-kz*kz) +  2*gxxy*kx*ky + 2*gxxz*kx*kz  +  2*gxyz*ky*kz
                        grry = gxxy*(kx*kx-kz*kz) + gyyy*(ky*ky-kz*kz) +  2*gxyy*kx*ky + 2*gxyz*kx*kz  +  2*gyyz*ky*kz
                        grrz = gxxz*(kx*kx-kz*kz) + gyyz*(ky*ky-kz*kz) +  2*gxyz*kx*ky - 2*(gxxx+gxyy)*kx*kz  - 2*(gxxy+gyyy)*ky*kz
                                
                        fkx[jy, jx, jz] += fk0[jy, jx, jz]*(grrx - grrr*kx)*cexp(1j*kdotdr)*(1-a2*k2)
                        fky[jy, jx, jz] += fk0[jy, jx, jz]*(grry - grrr*ky)*cexp(1j*kdotdr)*(1-a2*k2)
                        fkz[jy, jx, jz] += fk0[jy, jx, jz]*(grrz - grrr*kz)*cexp(1j*kdotdr)*(1-a2*k2)
        
        self.solve( v, np.concatenate(( self.fkx.ravel(), self.fky.ravel(), self.fkz.ravel() )) )
        return


    cpdef vortletV(self, np.ndarray v, double [:] r, double [:] V, double sigma=3, int NN=20):
        cdef:
            int i, nx, ny, nz , x, y, z, Nx, Ny, Nz, Np, jx, jy, jz
            double arg, facx, facy, facz, kx, ky, kz, vkx, vky, vkz
            double kdotdr, k2
        Nx, Ny, Nz = self.Nx, self.Ny, self.Nz 
        facx, facy, facz = self.facx, self.facy, self.facz
        Np = self.Np
        
        self.fourierFk(sigma, NN)  # construct the fk0 
            
        cdef complex [:, :, :] fk0 = self.fk0
        cdef complex [:, :, :] fkx = self.fkx
        cdef complex [:, :, :] fky = self.fky
        cdef complex [:, :, :] fkz = self.fkz

        for jz in prange(Nz, nogil=True): 
            for jy in range(Ny): 
                for jx in range(Nx): 
                    for i in range(Np):
                        kx = jx*facx if jx <= Nx / 2 else (-Nx+jx)*facx
                        ky = jy*facy if jy <= Ny / 2 else (-Ny+jy)*facy
                        kz = jz*facz if jz <= Nz / 2 else (-Nz+jz)*facz
                        kdotdr = kx*(r[i]-Nx/2) + ky*(r[i+1]-Ny/2) + kz*(r[i+2]-Nz/2)
                        
                        vkx = V[i]     *kx  + V[i+2]*ky + V[i+3*Np] *kz     # sxx, syy, sxy, sxz, syz
                        vky = V[i+2]*kx  + V[i+1]  *ky + V[i+4*Np] *kz
                        vkz = V[i+3*Np]*kx  + V[i+4*Np]*ky - (V[i]+V[i+1])*kz
                        
                        fkx[jy, jx, jz] += fk0[jy, jx, jz]*(ky*vkz - kz*vky)*cexp(1j*kdotdr)
                        fky[jy, jx, jz] += fk0[jy, jx, jz]*(kz*vkx - kx*vkz)*cexp(1j*kdotdr)
                        fkz[jy, jx, jz] += fk0[jy, jx, jz]*(kx*vky - ky*vkx)*cexp(1j*kdotdr)
        self.solve( v, np.concatenate(( self.fkx.ravel(), self.fky.ravel(), self.fkz.ravel() )) )
        return


    cpdef spinletV(self, np.ndarray v, double [:] r, double [:] M, double sigma=3, int NN=20):
        cdef:
            int i, nx, ny, nz , x, y, z, Nx, Ny, Nz, Np, jx, jy, jz
            double arg, facx, facy, facz, kx, ky, kz, mrrr, mrrx, mrry, mrrz, mxxx, myyy, mxxy, mxxz, mxyy, mxyz, myyz
            double kdotdr, k2
        Nx, Ny, Nz = self.Nx, self.Ny, self.Nz 
        facx, facy, facz = self.facx, self.facy, self.facz
        Np = self.Np
        
        self.fourierFk(sigma, NN)  # construct the fk0 
            
        cdef complex [:, :, :] fk0 = self.fk0
        cdef complex [:, :, :] fkx = self.fkx
        cdef complex [:, :, :] fky = self.fky
        cdef complex [:, :, :] fkz = self.fkz
                
        for i in prange(Np, nogil=True):
            mxxx = M[7*i]
            myyy = M[7*i+1]
            mxxy = M[7*i+2]
            mxxz = M[7*i+3*Np]
            mxyy = M[7*i+4*Np]
            mxyz = M[7*i+5*Np]
            myyz = M[7*i+6*Np]

        for jz in prange(Nz, nogil=True): 
            for jy in range(Ny): 
                for jx in range(Nx): 
                    for i in range(Np):
                        kx = jx*facx if jx <= Nx / 2 else (-Nx+jx)*facx
                        ky = jy*facy if jy <= Ny / 2 else (-Ny+jy)*facy
                        kz = jz*facz if jz <= Nz / 2 else (-Nz+jz)*facz
                        kdotdr = kx*(r[i]-Nx/2) + ky*(r[i+1]-Ny/2) + kz*(r[i+2]-Nz/2)
                        
                        mrrr = mxxx*kx*(kx*kx-3*kz*kz) + 3*mxxy*ky*(kx*kx-kz*kz) + mxxz*kz*(3*kx*kx-kz*kz) +\
                                 3*mxyy*kx*(ky*ky-kz*kz) + 6*mxyz*kx*ky*kz + myyy*ky*(ky*ky-3*kz*kz) +  myyz*kz*(3*ky*ky-kz*kz) 
                        mrrx = mxxx*(kx*kx-kz*kz) + mxyy*(ky*ky-kz*kz) +  2*mxxy*kx*ky + 2*mxxz*kx*kz  +  2*mxyz*ky*kz
                        mrry = mxxy*(kx*kx-kz*kz) + myyy*(ky*ky-kz*kz) +  2*mxyy*kx*ky + 2*mxyz*kx*kz  +  2*myyz*ky*kz
                        mrrz = mxxz*(kx*kx-kz*kz) + myyz*(ky*ky-kz*kz) +  2*mxyz*kx*ky - 2*(mxxx+mxyy)*kx*kz  - 2*(mxxy+myyy)*ky*kz
                                
                        fkx[jy, jx, jz] += fk0[jy, jx, jz]*(ky*mrrz - kz*mrry)*cexp(1j*kdotdr)
                        fky[jy, jx, jz] += fk0[jy, jx, jz]*(kz*mrrx - kx*mrrz)*cexp(1j*kdotdr)
                        fkz[jy, jx, jz] += fk0[jy, jx, jz]*(kx*mrry - ky*mrrx)*cexp(1j*kdotdr)
        
        self.solve( v, np.concatenate(( self.fkx.ravel(), self.fky.ravel(), self.fkz.ravel() )) )
        return


    cpdef solve(self, np.ndarray v, np.ndarray fk ):
        ''' solve takes two numpy arrays v and fk.  Here, fk is 
        the Fourier transform of the force field on the grid and v is an empty 
        arrray of same size. It return  the updated value of v = f(1-k k/k^2)/k^2''' 
        cdef int jx, jy, jz, Nx, Ny, Nz
        cdef double facx, facy, facz, a2, k2, kx, ky, kz, skx, sky, skz
        cdef double complex fdotk
        facx = self.facx
        facy = self.facy
        facz = self.facz
        Nx, Ny, Nz = self.Nx, self.Ny, self. Nz
        cdef int eqS = Nx*Ny*Nz
        cdef:
            complex [:,:,:] fkx = fk[      :eqS  ].reshape(Nx, Ny, Nz)
            complex [:,:,:] fky = fk[eqS  :2*eqS ].reshape(Nx, Ny, Nz)
            complex [:,:,:] fkz = fk[2*eqS:3*eqS ].reshape(Nx, Ny, Nz)
            complex [:,:,:] vkx = self.vkx
            complex [:,:,:] vky = self.vky
            complex [:,:,:] vkz = self.vkz
        
        for jz in prange(Nz, nogil=True): 
            for jy in range(Ny): 
                for jx in range(Nx): 
                    kx = facx*jx if jx <= Nx / 2 else facx*(-Nx+jx)
                    ky = facy*jy if jy <= Ny / 2 else facy*(-Ny+jx)
                    kz = facz*jz if jz <= Nz / 2 else facz*(-Nz+jx)
                    if kx !=0  or ky != 0.0 or kz!= 0.0:
                        k2 = kx*kx + ky*ky + kz*kz
                        fdotk = kx*fkx[jy, jx, jz] + ky*fky[jy, jx, jz] + kz*fkz[jy, jx, jz]
                        
                        vkx[jy, jx, jz] = ( fkx[jy, jx, jz] - fdotk*((kx / k2)) ) / k2
                        vky[jy, jx, jz] = ( fky[jy, jx, jz] - fdotk*((ky / k2)) ) / k2 
                        vkz[jy, jx, jz] = ( fkz[jy, jx, jz] - fdotk*((kz / k2)) ) / k2 
                    else:
                        pass
        vkx[0, 0, 0] = 0.0;        vky[0, 0, 0] = 0.0;        vkz[0, 0, 0] = 0.0;
        
        v[     :eqS  ] = np.real(np.fft.ifftn(self.vky)).ravel()
        v[eqS  :2*eqS] = np.real(np.fft.ifftn(self.vky)).ravel()
        v[2*eqS:3*eqS] = np.real(np.fft.ifftn(self.vkz)).ravel()
        return

    
    cdef fourierFk(self, double sigma, int NN = 20):
        ''' this module construct an initial Gaussian mollified force force on a grid.
        And returns the Fourier transform of this which can then be used by the method solve()'''
        cdef:
            double scale = pow(2*PI*sigma*sigma, 3/2) 
            int Nx, Ny, Nz, nx, ny, nz
            double [:, :, :] fx0 = self.fx0
            double arg
        Nx, Ny, Nz = self.Nx, self.Ny, self. Nz
        
       
        for nz in prange(Nz, nogil=True):
            for ny in range(Ny):
                for nx in range(Nx):
                    arg = ( (nx-Nx/2 )*(nx-Nx/2) + (ny -Ny/2)*(ny-Ny/2) + (nz -Nz/2)*(nz-Nz/2))/ (2*sigma*sigma)
                    fx0[ny, nx, nz] += exp(-arg)*scale
 
        self.fk0 = np.fft.fftn(self.fx0)
        return


    cpdef interpolate(self, double [:] V, double [:] r, np.ndarray vv, double sigma=3, int NN=20):
        cdef int i, nx, ny, nz, x, y, z, Nx, Ny, Nz, Np
        cdef double arg, pdotdr 
        cdef double scale = pow(2*PI*sigma*sigma, 3/2) 
        
            
        Nx, Ny, Nz = self.Nx, self.Ny, self.Nz 
        Np = self.Np    
        cdef double [:,:,:] vx = vv[          :Nx*Ny*Nz  ] 
        cdef double [:,:,:] vy = vv[Nx*Ny*Nz  :2*Nx*Ny*Nz]
        cdef double [:,:,:] vz = vv[2*Nx*Ny*Nz:3*Nx*Ny*Nz]
            
        
        for nz in range(2*NN+2):
            for ny in range(2*NN+2):
                for nx in range(2*NN+2):
                    for i in range(Np):
                        i = i*3

                        x = int(r[i])        #NOTE works for positive coordinates!
                        y = int(r[i+1]) 
                        z = int(r[i+2]) 
                        x = x - NN + nx
                        y = y - NN + ny
                        z = z - NN + nz
                        arg = ( (x - r[i])*(x-r[i]) + (y - r[i+1])*(y-r[i+1]) +(z - r[i+2])*(z-r[i+2]) )/ (2 * sigma*sigma)
                        x = x % Nx
                        y = y % Ny
                        z = z % Nz
                    
                    V[i]   += exp(-arg)*scale*vx[y, x, z]
                    V[i+1] += exp(-arg)*scale*vy[y, x, z]
                    V[i+2] += exp(-arg)*scale*vz[y, x, z]
