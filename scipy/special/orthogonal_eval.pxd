# -*- cython -*-
"""
Evaluate orthogonal polynomial values using recurrence relations.

References
----------

.. [AMS55] Abramowitz & Stegun, Section 22.5.

.. [MH] Mason & Handscombe, Chebyshev Polynomials, CRC Press (2003).

.. [LP] P. Levrie & R. Piessens, A note on the evaluation of orthogonal
        polynomials using recurrence relations, Internal Report TW74 (1985)
        Dept. of Computer Science, K.U. Leuven, Belgium 
        https://lirias.kuleuven.be/handle/123456789/131600

"""
#
# Authors: Pauli Virtanen, Eric Moore
#

#------------------------------------------------------------------------------
# Direct evaluation of polynomials
#------------------------------------------------------------------------------
cimport cython
from libc.math cimport sqrt, exp

from numpy cimport npy_cdouble

cdef extern from "cephes.h":
    double Gamma(double x) nogil
    double lgam(double x) nogil
    double hyp2f1_wrap "hyp2f1" (double a, double b, double c, double x) nogil 

cdef extern from "specfun_wrappers.h":
    double hyp1f1_wrap(double a, double b, double x) nogil
    npy_cdouble chyp2f1_wrap( double a, double b, double c, npy_cdouble z) nogil 
    npy_cdouble chyp1f1_wrap( double a, double b, npy_cdouble z) nogil

cdef extern from "c_misc/misc.h":
    double gammasgn(double x) nogil

# Fused type wrappers

ctypedef fused number_t:
    double
    double complex

cdef inline number_t hyp2f1(double a, double b, double c, number_t z) nogil:
    cdef npy_cdouble r
    if number_t is double:
        return hyp2f1_wrap(a, b, c, z)
    else:
        r = chyp2f1_wrap(a, b, c, (<npy_cdouble*>&z)[0])
        return (<number_t*>&r)[0]

cdef inline number_t hyp1f1(double a, double b, number_t z) nogil:
    cdef npy_cdouble r
    if number_t is double:
        return hyp1f1_wrap(a, b, z)
    else:
        r = chyp1f1_wrap(a, b, (<npy_cdouble*>&z)[0])
        return (<number_t*>&r)[0]

#-----------------------------------------------------------------------------
# Binomial coefficient
#-----------------------------------------------------------------------------

cdef inline double binom(double n, double k) nogil:
    return gammasgn(n+1)*gammasgn(k+1)*gammasgn(1+n-k)*exp(lgam(n+1) - lgam(k+1) - lgam(1+n-k))

#-----------------------------------------------------------------------------
# Jacobi
#-----------------------------------------------------------------------------

cdef inline number_t eval_jacobi(double n, double alpha, double beta, number_t x) nogil:
    cdef double a, b, c, d 
    cdef number_t g
    
    d = binom(n+alpha, n)
    a = -n
    b = n + alpha + beta + 1
    c = alpha + 1
    g = 0.5*(1-x)
    return d * hyp2f1(a, b, c, g)

@cython.cdivision(True)
cdef inline double eval_jacobi_l(long n, double alpha, double beta, double x) nogil:
    cdef long kk
    cdef double p, d
    cdef double k

    if n < 0:
        return 0.0
    elif n == 0:
        return 1.0
    elif n == 1:
        return 0.5*(2*(alpha+1)+(alpha+beta+2)*(x-1)) 
    else:
        d = (alpha+beta+2)*(x - 1) / (2*(alpha+1))
        p = d + 1 
        for kk in range(n-1):
            k = kk+1.0
            d = (2*k+alpha+beta)/(2*(k+alpha+1)*(k+alpha+beta+1)*(2*k+alpha+beta))*(x-1)*p + (2*k*(k+alpha)*(2*k+alpha+beta+2))/(2*(k+alpha+1)*(k+alpha+beta+1)*(2*k+alpha+beta)) * d
            p = d + p
        return binom(n+alpha, n)*p

#-----------------------------------------------------------------------------
# Shifted Jacobi
#-----------------------------------------------------------------------------

cdef inline number_t eval_sh_jacobi(double n, double p, double q, number_t x) nogil:
    cdef double factor

    factor = exp(lgam(1+n) + lgam(n+p) - lgam(2*n+p))
    return factor * eval_jacobi(n, p-q, q-1, 2*x-1) 

cdef inline double eval_sh_jacobi_l(long n, double p, double q, double x) nogil:
    cdef double factor

    factor = exp(lgam(1+n) + lgam(n+p) - lgam(2*n+p))
    return factor * eval_jacobi_l(n, p-q, q-1, 2*x-1)

#-----------------------------------------------------------------------------
# Gegenbauer (Ultraspherical)
#-----------------------------------------------------------------------------

@cython.cdivision(True)
cdef inline number_t eval_gegenbauer(double n, double alpha, number_t x) nogil:
    cdef double a, b, c, d
    cdef number_t g

    d = Gamma(n+2*alpha)/Gamma(1+n)/Gamma(2*alpha)
    a = -n
    b = n + 2*alpha
    c = alpha + 0.5
    g = (1-x)/2.0
    return d * hyp2f1(a, b, c, g)

@cython.cdivision(True)
cdef inline double eval_gegenbauer_l(long n, double alpha, double x) nogil:
    cdef long kk
    cdef double p, d
    cdef double k

    if n < 0:
        return 0.0
    elif n == 0:
        return 1.0
    elif n == 1:
        return 2*alpha*x
    elif alpha == 0.0:
        return eval_gegenbauer(n, alpha, x)
    else:
        d = x - 1
        p = x 
        for kk in range(n-1):
            k = kk+1.0
            d = (2*(k+alpha)/(k+2*alpha))*(x-1)*p + (k/(k+2*alpha)) * d
            p = d + p
        return binom(n+2*alpha-1, n)*p

#-----------------------------------------------------------------------------
# Chebyshev 1st kind (T)
#-----------------------------------------------------------------------------

cdef inline number_t eval_chebyt(double n, number_t x) nogil:
    cdef double a, b, c, d
    cdef number_t g

    d = 1.0
    a = -n
    b = n
    c = 0.5
    g = 0.5*(1-x)
    return hyp2f1(a, b, c, g)

cdef inline double eval_chebyt_l(long k, double x) nogil:
    # Use Chebyshev T recurrence directly, see [MH]
    cdef long m
    cdef double b2, b1, b0

    b2 = 0
    b1 = -1
    b0 = 0
    x = 2*x
    for m in range(k+1):
        b2 = b1
        b1 = b0
        b0 = x*b1 - b2
    return (b0 - b2)/2.0

#-----------------------------------------------------------------------------
# Chebyshev 2st kind (U)
#-----------------------------------------------------------------------------

cdef inline number_t eval_chebyu(double n, number_t x) nogil:
    cdef double a, b, c, d
    cdef number_t g

    d = n+1
    a = -n
    b = n+2
    c = 1.5
    g = 0.5*(1-x)
    return d*hyp2f1(a, b, c, g)

cdef inline double eval_chebyu_l(long k, double x) nogil:
    cdef long m
    cdef double b2, b1, b0

    b2 = 0
    b1 = -1
    b0 = 0
    x = 2*x
    for m in range(k+1):
        b2 = b1
        b1 = b0
        b0 = x*b1 - b2
    return b0 

#-----------------------------------------------------------------------------
# Chebyshev S
#-----------------------------------------------------------------------------

cdef inline number_t eval_chebys(double n, number_t x) nogil:
    return eval_chebyu(n, 0.5*x)

cdef inline double eval_chebys_l(long n, double x) nogil:
    return eval_chebyu_l(n, 0.5*x)

#-----------------------------------------------------------------------------
# Chebyshev C
#-----------------------------------------------------------------------------

cdef inline number_t eval_chebyc(double n, number_t x) nogil:
    return 2*eval_chebyt(n, 0.5*x)

cdef inline double eval_chebyc_l(long n, double x) nogil:
    return 2*eval_chebyt_l(n, 0.5*x)

#-----------------------------------------------------------------------------
# Chebyshev 1st kind shifted
#-----------------------------------------------------------------------------

cdef inline number_t eval_sh_chebyt(double n, number_t x) nogil:
    return eval_chebyt(n, 2*x-1)

cdef inline double eval_sh_chebyt_l(long n, double x) nogil:
    return eval_chebyt_l(n, 2*x-1)

#-----------------------------------------------------------------------------
# Chebyshev 2st kind shifted
#-----------------------------------------------------------------------------

cdef inline number_t eval_sh_chebyu(double n, number_t x) nogil:
    return eval_chebyu(n, 2*x-1)

cdef inline double eval_sh_chebyu_l(long n, double x) nogil:
    return eval_chebyu_l(n, 2*x-1)

#-----------------------------------------------------------------------------
# Legendre
#-----------------------------------------------------------------------------

cdef inline number_t eval_legendre(double n, number_t x) nogil:
    cdef double a, b, c, d
    cdef number_t g

    d = 1
    a = -n
    b = n+1
    c = 1
    g = 0.5*(1-x)
    return d*hyp2f1(a, b, c, g)

@cython.cdivision(True)
cdef inline double eval_legendre_l(long n, double x) nogil:
    cdef long kk
    cdef double p, d
    cdef double k

    if n < 0:
        return 0.0
    elif n == 0:
        return 1.0
    elif n == 1:
        return x
    else:
        d = x - 1
        p = x 
        for kk in range(n-1):
            k = kk+1.0
            d = ((2*k+1)/(k+1))*(x-1)*p + (k/(k+1)) * d
            p = d + p
        return p

#-----------------------------------------------------------------------------
# Legendre Shifted
#-----------------------------------------------------------------------------

cdef inline number_t eval_sh_legendre(double n, number_t x) nogil:
    return eval_legendre(n, 2*x-1)

cdef inline double eval_sh_legendre_l(long n, double x) nogil:
    return eval_legendre_l(n, 2*x-1)

#-----------------------------------------------------------------------------
# Generalized Laguerre
#-----------------------------------------------------------------------------

cdef inline number_t eval_genlaguerre(double n, double alpha, number_t x) nogil:
    cdef double a, b, d
    cdef number_t g

    d = binom(n+alpha, n)
    a = -n
    b = alpha + 1
    g = x
    return d * hyp1f1(a, b, g)

@cython.cdivision(True)
cdef inline double eval_genlaguerre_l(long n, double alpha, double x) nogil:
    cdef long kk
    cdef double p, d
    cdef double k

    if n < 0:
        return 0.0
    elif n == 0:
        return 1.0
    elif n == 1:
        return -x+alpha+1
    else:
        d = -x/(alpha+1) 
        p = d + 1 
        for kk in range(n-1):
            k = kk+1.0
            d = -x/(k+alpha+1)*p + (k/(k+alpha+1)) * d
            p = d + p
        return binom(n+alpha, n)*p

#-----------------------------------------------------------------------------
# Laguerre
#-----------------------------------------------------------------------------

cdef inline number_t eval_laguerre(double n, number_t x) nogil:
    return eval_genlaguerre(n, 0., x)

cdef inline double eval_laguerre_l(long n, double x) nogil:
    return eval_genlaguerre_l(n, 0., x)

#-----------------------------------------------------------------------------
# Hermite (physicist's)
#-----------------------------------------------------------------------------

@cython.cdivision(True)
cdef inline double eval_hermite(long n, double x) nogil:
    cdef long m

    if n % 2 == 0:
        m = n/2
        return ((-1)**m * 2**(2*m) * Gamma(1+m)
                 * eval_genlaguerre_l(m, -0.5, x**2))
    else:
        m = (n-1)/2
        return ((-1)**m * 2**(2*m+1) * Gamma(1+m)
                  * x * eval_genlaguerre_l(m, 0.5, x**2))

#-----------------------------------------------------------------------------
# Hermite (statistician's)
#-----------------------------------------------------------------------------

@cython.cdivision(True)
cdef inline double eval_hermitenorm(long n, double x) nogil:
    return eval_hermite(n, x/sqrt(2)) * 2**(-n/2.0)
