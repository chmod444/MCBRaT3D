! Copyight 2003-2009, Regents of the University of Colorado. All right reserved
! Use and duplication is permitted under the terms of the 
!   GNU public license, V2 : http://www.gnu.org/licenses/old-licenses/gpl-2.0.html
! NASA has special rights noted in License.txt

! $Revision: 6 $, $Date: 2009-03-10 20:13:07 +0000 (Tue, 10 Mar 2009) $
! $URL: http://i3rc-monte-carlo-model.googlecode.com/svn/trunk/Code/monteCarloIllumination.f95 $
module monteCarloIllumination
  ! Provides an object representing a series of photons. The object specifies the 
  !   initial x, y position and direction. 
  ! In principle any arbitrary illumination condition can be specified. 
  ! Initial x, y positions are between 0 and 1, and must be scaled by the Monte Carlo
  !   integrator. 
  ! On input, azimuth is in degrees and zenith angle is specified as the cosine. 
  ! On output, azimuth is in radians (0, 2 pi) and solar mu is negative (down-going). 
  
  use ErrorMessages
  use RandomNumbers
  implicit none
  private

  !------------------------------------------------------------------------------------------
  ! Constants
  !------------------------------------------------------------------------------------------
  logical, parameter :: useFiniteSolarWidth = .false. 
  real,    parameter :: halfAngleDiamaterOfSun = 0.25 ! degrees
  
  !------------------------------------------------------------------------------------------
  ! Type (object) definitions
  !------------------------------------------------------------------------------------------
  type photonStream
    integer                     :: currentPhoton = 0
    real, dimension(:), pointer :: xPosition    => null()
    real, dimension(:), pointer :: yPosition    => null()
    real, dimension(:), pointer :: zPosition    => null()
    real, dimension(:), pointer :: solarMu      => null()
    real, dimension(:), pointer :: solarAzimuth => null()
  end type photonStream
  
  !------------------------------------------------------------------------------------------
  ! Overloading
  !------------------------------------------------------------------------------------------
  interface new_PhotonStream
    module procedure newPhotonStream_Directional, newPhotonStream_RandomAzimuth, &
                     newPhotonStream_Flux, newPhotonStream_Spotlight, newPhotonStream_LWemission
  end interface new_PhotonStream
  !------------------------------------------------------------------------------------------
  ! What is visible? 
  !------------------------------------------------------------------------------------------
  public :: photonStream 
  public :: new_PhotonStream, finalize_PhotonStream, morePhotonsExist, getNextPhoton, emission_weighting
contains
  !------------------------------------------------------------------------------------------
  ! Code
  !------------------------------------------------------------------------------------------
  ! Initialization: Routines to create streams of incoming photons
  !------------------------------------------------------------------------------------------
  function newPhotonStream_Directional(solarMu, solarAzimuth, &
                                       numberOfPhotons, randomNumbers, status) result(photons)
    ! Create a set of incoming photons with specified initial zenith angle cosine and  
    !   azimuth. 
    real,                       intent(in   ) :: solarMu, solarAzimuth
    integer                                   :: numberOfPhotons
    type(randomNumberSequence), intent(inout) :: randomNumbers
    type(ErrorMessage),         intent(inout) :: status
    type(photonStream)                        :: photons
    
        ! Local variables
    integer :: i
    
    ! Checks: are input parameters specified correctly? 
    if(numberOfPhotons <= 0) &
      call setStateToFailure(status, "setIllumination: must ask for non-negative number of photons.")
    if(solarAzimuth < 0. .or. solarAzimuth > 360.) &
      call setStateToFailure(status, "setIllumination: solarAzimuth out of bounds")
    if(abs(solarMu) > 1. .or. abs(solarMu) <= tiny(solarMu)) &
      call setStateToFailure(status, "setIllumination: solarMu out of bounds")
    
    if(.not. stateIsFailure(status)) then
      allocate(photons%xPosition(numberOfPhotons),   photons%yPosition(numberOfPhotons), &
               photons%zPosition(numberOfPhotons),                                       &
               photons%solarMu(numberOfPhotons), photons%solarAzimuth(numberOfPhotons))
                        
      do i = 1, numberOfPhotons
        ! Random initial positions 
        photons%xPosition(   i) = getRandomReal(randomNumbers)
        photons%yPosition(   i) = getRandomReal(randomNumbers)
      end do
      photons%zPosition(:) = 1. - spacing(1.) 
      ! Specified inital directions
      photons%solarMu( :) = -abs(solarMu)
      photons%solarAzimuth(:) = solarAzimuth * acos(-1.) / 180. 
      photons%currentPhoton = 1
      
      call setStateToSuccess(status)
   end if   
  end function newPhotonStream_Directional
  ! ------------------------------------------------------
  function newPhotonStream_RandomAzimuth(solarMu, numberOfPhotons, randomNumbers, status) &
           result(photons)
    ! Create a set of incoming photons with specified initial zenith angle cosine but
    !  random initial azimuth. 
    real,                       intent(in   ) :: solarMu
    integer                                   :: numberOfPhotons
    type(randomNumberSequence), intent(inout) :: randomNumbers
    type(ErrorMessage),         intent(inout) :: status
    type(photonStream)                        :: photons
    
    ! Local variables
    integer :: i
    
    ! Checks: are input parameters specified correctly? 
    if(numberOfPhotons <= 0) &
      call setStateToFailure(status, "setIllumination: must ask for non-negative number of photons.")
    if(abs(solarMu) > 1. .or. abs(solarMu) <= tiny(solarMu)) &
      call setStateToFailure(status, "setIllumination: solarMu out of bounds")
    
    if(.not. stateIsFailure(status)) then
      allocate(photons%xPosition(numberOfPhotons),   photons%yPosition(numberOfPhotons), &
               photons%zPosition(numberOfPhotons),                                       &
               photons%solarMu(numberOfPhotons), photons%solarAzimuth(numberOfPhotons))
      do i = 1, numberOfPhotons
        ! Random initial positions 
        photons%xPosition(   i) = getRandomReal(randomNumbers)
        photons%yPosition(   i) = getRandomReal(randomNumbers)
        ! Random initial azimuth
        photons%solarAzimuth(i) = getRandomReal(randomNumbers) * 2. * acos(-1.) 
      end do
      photons%zPosition(:) = 1. - spacing(1.) 
      ! but specified inital mu
      photons%solarMu( :) = -abs(solarMu)
      photons%currentPhoton = 1
      
      call setStateToSuccess(status)
    end if   
 end function newPhotonStream_RandomAzimuth
 ! ------------------------------------------------------
 function newPhotonStream_Flux(numberOfPhotons, randomNumbers, status) result(photons)
    ! Create a set of incoming photons with random initial azimuth and initial
    !  mus constructed so the solar flux on the horizontal is equally weighted
    !  in mu (daytime average is 1/2 solar constant; this is "global" average weighting)
    integer                                   :: numberOfPhotons
    type(randomNumberSequence), intent(inout) :: randomNumbers
    type(ErrorMessage),         intent(inout) :: status
    type(photonStream)                        :: photons
    
    ! Local variables
    integer :: i
    
    ! Checks
    if(numberOfPhotons <= 0) &
      call setStateToFailure(status, "setIllumination: must ask for non-negative number of photons.")
     
    if(.not. stateIsFailure(status)) then
      allocate(photons%xPosition(numberOfPhotons),   photons%yPosition(numberOfPhotons), &
               photons%zPosition(numberOfPhotons),                                       &
               photons%solarMu(numberOfPhotons),  photons%solarAzimuth(numberOfPhotons))
               
      do i = 1, numberOfPhotons
        ! Random initial positions
        photons%xPosition(   i) = getRandomReal(randomNumbers)
        photons%yPosition(   i) = getRandomReal(randomNumbers)
        ! Random initial directions
        photons%solarMu(     i) = -sqrt(getRandomReal(randomNumbers)) 
        photons%solarAzimuth(i) = getRandomReal(randomNumbers) * 2. * acos(-1.)
      end do
      photons%zPosition(:) = 1. - spacing(1.) 
      
      photons%currentPhoton = 1
      call setStateToSuccess(status)  
    end if     
  end function newPhotonStream_Flux
  !------------------------------------------------------------------------------------------
  function newPhotonStream_Spotlight(solarMu, solarAzimuth, solarX, solarY, &
                                     numberOfPhotons, randomNumbers, status) result(photons)
    ! Create a set of incoming photons with specified initial zenith angle cosine and  
    !   azimuth. 
    real,                       intent(in   ) :: solarMu, solarAzimuth, solarX, solarY
    integer                                   :: numberOfPhotons
    type(randomNumberSequence), optional, &
                                intent(inout) :: randomNumbers
    type(ErrorMessage),         intent(inout) :: status
    type(photonStream)                        :: photons
        
    ! Checks: are input parameters specified correctly? 
    if(numberOfPhotons <= 0) &
      call setStateToFailure(status, "setIllumination: must ask for non-negative number of photons.")
    if(solarAzimuth < 0. .or. solarAzimuth > 360.) &
      call setStateToFailure(status, "setIllumination: solarAzimuth out of bounds")
    if(abs(solarMu) > 1. .or. abs(solarMu) <= tiny(solarMu)) &
      call setStateToFailure(status, "setIllumination: solarMu out of bounds")
    if(abs(solarX) > 1. .or. abs(solarX) <= 0. .or. &
       abs(solarY) > 1. .or. abs(solarY) <= 0. )    &
      call setStateToFailure(status, "setIllumination: x and y positions must be between 0 and 1")
    
    if(.not. stateIsFailure(status)) then
      allocate(photons%xPosition(numberOfPhotons),   photons%yPosition(numberOfPhotons), &
               photons%zPosition(numberOfPhotons),                                       &
               photons%solarMu(numberOfPhotons), photons%solarAzimuth(numberOfPhotons))
                        
      ! Specified inital directions and position
      photons%solarMu( :) = -abs(solarMu)
      photons%solarAzimuth(:) = solarAzimuth * acos(-1.) / 180. 
      photons%xPosition(:) = solarX
      photons%yPosition(:) = solarY
      photons%zPosition(:) = 1. - spacing(1.) 
      photons%currentPhoton = 1
      
      call setStateToSuccess(status)
   end if   
  end function newPhotonStream_Spotlight

!-------------------------------------------------------------------------------------------
  function newPhotonStream_LWemission(numberOfPhotons, atmsColumn_photons, vertical_weights, nx, ny, nz, randomNumbers, status) result(photons)
    ! Create a set of emitted photons with random initial azimuth, random 
    ! mus, and random x,y,z location within the domain. This is the LW source from the atmosphere
    ! and surface. The x,y,z locations are weighted based on the power emitted 
    ! from each column, voxel, pixel, in both the atmosphere and surface.
    ! Written by Alexandra Jones at the University of Illinois, Urbana-Champaign. Fall 2011

    implicit none
    
    integer, intent(in)                             :: numberOfPhotons, nx, ny, nz
    type(randomNumberSequence), intent(inout)       :: randomNumbers
    type(ErrorMessage),         intent(inout)       :: status
    type(photonStream)                              :: photons
    integer, dimension(1:nx,1:ny), intent(in)       :: atmsColumn_photons
    real, dimension(1:nx,1:ny,1:nz+1), intent(in)   :: vertical_weights

    ! Local variables
    integer :: i, numberOfAtmsPhotons, startPhoton, mi, ni, iz
    real    :: m, n, RN, test
    
   
    ! Checks
    if(numberOfPhotons <= 0) &
      call setStateToFailure(status, "setIllumination: must ask for non-negative number of photons.")
       
    if(.not. stateIsFailure(status)) then
!PRINT *, "number of photons > 0"
      allocate(photons%xPosition(numberOfPhotons),   photons%yPosition(numberOfPhotons), &
               photons%zPosition(numberOfPhotons),                                       &
               photons%solarMu(numberOfPhotons),  photons%solarAzimuth(numberOfPhotons))

              
     ! divide the photons into sfc vs. atms sources 
   numberOfAtmsPhotons=MIN(numberOfPhotons,sum(atmsColumn_photons))
   if (numberOfAtmsPhotons .gt. 0) then
!PRINT *, "numberOfAtmsPhotons .gt. 0"
     startPhoton = 1
     
      do mi = 1, nx          ! x-index
        m= (mi-1) * 1.0/nx   ! left edge of pixels in the x direction starting with 0
        do ni = 1, ny        ! y-index
          n = (ni-1) * 1.0/ny ! left edge of pixels in the y-direction starting with 0
          do i = startPhoton, MIN(numberOfPhotons,startPhoton+atmsColumn_photons(mi,ni)-1) ! Loop over photons from atms source one column at a time
!           do while (i .le. numberOfPhotons)
            ! Random initial positions
            RN = getRandomReal(randomNumbers)
!PRINT *, "i=", i, " RN=", RN
            do iz = nz, 1, -1     ! find the vertical poition starting from top down. In the current implementation there is no solar contribution so the nz+1 weighting is always 0. Therefore it makes sense to start from the next level down. Also the temperatures are at the centers of the levels not at the boundaries (the array dimensions ar nx, ny, nz).
!PRINT *, mi, m, ni, n, i, iz
              if (RN <= vertical_weights(mi,ni,iz)) then 
!PRINT *, "RN <= vertical weights iz=", iz
                RN = getRandomReal(randomNumbers)  ! a second random number needs to be chosen to determine where in the layer the photon is emitted.
                photons%zPosition(i) = ((iz-1)*(1.0-(2.*spacing(1.0)))/nz) + (RN/nz) ! The first term represents the fractional position of the layer bottom in the column, such that iz=1 corresponds to a position of 0. The second term respresents the position within the layer.
                exit
              end if
            end do  !loop over iz
            photons%xPosition(i) = m + getRandomReal(randomNumbers)*(1.0/nx) 
            photons%yPosition(i) = n + getRandomReal(randomNumbers)*(1.0/ny) 

            ! Random initial directions
            test=getRandomReal(randomNumbers)
!PRINT *, 'i=', i, ' atms_rand=', test 
            photons%solarMu(i) = 1-(2.*test)
!            photons%solarMu(i) = 1-(2.*getRandomReal(randomNumbers))    ! This formula is from section 10.5 of '3D radiative transfer in cloudy atmospheres'. These angles will stay the same...truly random numbers, since LW emission is isotropic. But the Mu no longer has to be negative. The name "solarMu" should really just be "sourceMu" 
            photons%solarAzimuth(i) = getRandomReal(randomNumbers) * 2. * acos(-1.)
            if (numberOfPhotons < numberOfAtmsPhotons)exit
!           end do
          end do  !loop over i
          if (numberOfPhotons < numberOfAtmsPhotons)exit
          startPhoton=startPhoton+atmsColumn_photons(mi,ni)
        end do  !loop over ni
        if (numberOfPhotons < numberOfAtmsPhotons)exit
      end do  !loop over mi

   end if

     if (numberOfPhotons > numberOfAtmsPhotons)then
      do i = numberOfAtmsPhotons+1, numberOfPhotons ! Loop over sfc source
        ! Random initial positions
        photons%xPosition(   i) = getRandomReal(randomNumbers) ! Assuming the surface temperature and emissivities are the same everywhere the x,y values don't need to be weighted
        photons%yPosition(   i) = getRandomReal(randomNumbers)
        ! Random initial directions
        test = getRandomReal(randomNumbers)
!PRINT *, 'i=', i, ' sfc_rand=', test
         photons%solarMu(     i) = sqrt(test)
!        photons%solarMu(     i) = sqrt(getRandomReal(randomNumbers))    ! This formula is from section 10.5 of '3D radiative trasnfer in cloudy atmospheres'. These angles will stay the same...truly random numbers, since LW emission is isotropic. But the Mu has to be positive for a sfc source. The name "solarMu" should really just be "sourceMu"
        photons%solarAzimuth(i) = getRandomReal(randomNumbers) * 2. * acos(-1.)
      end do  !loop over i
        photons%zPosition(numberOfAtmsPhotons+1:numberOfPhotons) = 0.0 ! must be from the sfc. Make sure this value makes sense for how the position is interpretted
     end if
!PRINT *,  ' photons%solarMu=', photons%solarMu(1)
      photons%currentPhoton = 1
      call setStateToSuccess(status) 
    end if    
  end function newPhotonStream_LWemission

   
  !------------------------------------------------------------------------------------------
  ! Are there more photons? Get the next photon in the sequence
  !------------------------------------------------------------------------------------------
  function morePhotonsExist(photons)
    type(photonStream), intent(inout) :: photons
    logical                           :: morePhotonsExist
    
    morePhotonsExist = photons%currentPhoton > 0 .and. &
                       photons%currentPhoton <= size(photons%xPosition)
  end function morePhotonsExist
  !------------------------------------------------------------------------------------------
  subroutine getNextPhoton(photons, xPosition, yPosition, zPosition, solarMu, solarAzimuth, status)
    type(photonStream), intent(inout) :: photons
    real,                 intent(  out) :: xPosition, yPosition, zPosition, solarMu, solarAzimuth
    type(ErrorMessage),   intent(inout) :: status
    
    ! Checks 
    ! Are there more photons?
    if(photons%currentPhoton < 1) &
      call setStateToFailure(status, "getNextPhoton: photons have not been initialized.")  
    if(.not. stateIsFailure(status)) then
      if(photons%currentPhoton > size(photons%xPosition)) &
        call setStateToFailure(status, "getNextPhoton: Ran out of photons")
    end if
      
    if(.not. stateIsFailure(status)) then
      xPosition    = photons%xPosition(photons%currentPhoton) 
      yPosition    = photons%yPosition(photons%currentPhoton)
      zPosition    = photons%zPosition(photons%currentPhoton)
      solarMu      = photons%solarMu(photons%currentPhoton)
!PRINT *, 'solarMu=', solarMu
      solarAzimuth = photons%solarAzimuth(photons%currentPhoton)
      photons%currentPhoton = photons%currentPhoton + 1
    end if
     
  end subroutine getNextPhoton
  !------------------------------------------------------------------------------------------
  ! Finalization
  !------------------------------------------------------------------------------------------
  subroutine finalize_PhotonStream(photons)
    type(photonStream), intent(inout) :: photons
    ! Free memory and nullify pointers. This leaves the variable in 
    !   a pristine state
    if(associated(photons%xPosition))    deallocate(photons%xPosition)
    if(associated(photons%yPosition))    deallocate(photons%yPosition)
    if(associated(photons%zPosition))    deallocate(photons%zPosition)
    if(associated(photons%solarMu))      deallocate(photons%solarMu)
    if(associated(photons%solarAzimuth)) deallocate(photons%solarAzimuth)
    
    photons%currentPhoton = 0
  end subroutine finalize_PhotonStream
!---------------------------------------------------------------------------------------------
! Compute number of photons emmitted from domain and surface when LW illumination is used
!---------------------------------------------------------------------------------------------
  subroutine emission_weighting(nx, ny, nz, numComponents, xPosition, yPosition, zPosition, lambda_u, totalPhotons, atmsColumn_photons, vertical_weights, atmsTemp, ssas, cumExt,  sfcTemp, emiss, totalFlux)
!Computes Planck Radiance for each surface and atmosphere pixel to determine the wieghting for the distribution of photons.
!Written by ALexandra Jones, University of Illinois, Urbana-Champaign, Fall 2011
     implicit none

     integer, intent(in)                               :: nx, ny, nz, numComponents, totalPhotons
     real, dimension(1:nx, 1:ny, 1:nz), intent(in)     :: atmsTemp, cumExt
     real, dimension(1:nx,1:ny,1:nz,1:numComponents), intent(in) :: ssas
     real, dimension(1:nz+1), intent(in)               :: zPosition
     real, dimension(1:ny+1), intent(in)               :: yPosition
     real, dimension(1:nx+1), intent(in)               :: xPosition
     real, intent(in)                                  :: sfcTemp, emiss, lambda_u
     integer, dimension(1:nx, 1:ny), intent(out)       :: atmsColumn_photons
     real, dimension(1:nx, 1:ny, 1:nz+1), intent(out)  :: vertical_weights
     real,                                intent(out)  :: totalFlux
     !Local variables
     integer                                           :: ix, iy, iz
     real                                              :: columnTotal, sfcPlanckRad, sfcPower, atmsPhotons,  atmsPower, totalPower, totalAbsCoef, b, lambda
     real, dimension(1:nz)                             :: dz
     real, dimension(1:ny)                             :: dy
     real, dimension(1:nx)                             :: dx
     real, dimension(1:nx,1:ny,1:nz)                   :: atmsPlanckRad
     real, dimension(1:nx, 1:ny)                       :: atmsColumn_power

     real, parameter                                   :: h=6.62606957e-34 !planck's constant [Js]
     real, parameter                                   :: c=2.99792458e+8 !speed of light [ms^-1]
     real, parameter                                   :: k=1.3806488e-23 !boltzman constant [J/K molecule]
     real, parameter                                   :: a=2.0*h*c**2  
     real, parameter                                   :: Pi=4*ATAN(1.0)

     lambda=lambda_u/(10**6) ! convert lambda from micrometers to meters
     b=h*c/(k*lambda)
!calculate arrays of depths from the position arrays in km
     dz(1:nz)=zPosition(2:nz+1)-zPosition(1:nz)
     dy(1:ny)=yPosition(2:ny+1)-yPosition(1:ny)
     dx(1:nx)=xPosition(2:nx+1)-xPosition(1:nx)

!first compute atms planck radiances then combine algorithms from mcarWld_fMC_srcDist and mcarWld_fMC_srcProf to determine the  weights of each voxel in each column and the total number of photons assigned to each column, taking into consideration the ones that would be emitted from the surface instead.
     if (emiss .eq. 0.0)then
        sfcPower=0.0
     else
        sfcPlanckRad=(a/((lambda**5)*(exp(b/sfcTemp)-1)))/(10**6)
        sfcPower= Pi*emiss*sfcPlanckRad*(xPosition(nx+1)-xPosition(1))*(yPosition(ny+1)-yPosition(1))*(1000**2)     ! [W] factor of 1000^2 needed to convert area from km to m
     end if


     vertical_weights=0.0  ! the weight at nz+1 should be 0 since we aren't considering a solar source (according to MCARATs algorithm)
     do ix = 1, nx
       do iy = 1, ny
         do iz = nz, 1, -1
           atmsPlanckRad(ix,iy,iz)= (a/((lambda**5)*(exp(b/atmsTemp(ix,iy,iz))-1)))/(10**6) ! the 10^-6 factor converts it from Wsr^-1m^-3 to Wm^-2sr^-1micron^-1

           totalAbsCoef=cumExt(ix,iy,iz)*(1-sum(ssas(ix,iy,iz,:)))
           vertical_weights(ix,iy,iz) = vertical_weights(ix,iy,iz+1) + 4.0*Pi* atmsPlanckRad(ix,iy,iz) * totalAbsCoef*dz(iz)     ! [Wm^-2] 
         end do
          columnTotal=vertical_weights(ix,iy,1)
          if (columnTotal .eq. 0.0)then
               atmsColumn_power(ix,iy)= 0.0
          else
               vertical_weights(ix,iy,:)=vertical_weights(ix,iy,:)/columnTotal     ! normalized
               vertical_weights(ix,iy,1)=1.0     ! need this to be 1 for algorithm used to select emitting voxel
               atmsColumn_power(ix,iy)=columnTotal*dx(ix)*dy(iy)*(1000**2)     ! [W] total power emitted by column. Factor of 1000^2 is to convert dx and dy from km to m
          end if
       end do 
     end do
     atmsPower=sum(atmsColumn_power)
      
     totalPower=sfcPower + atmsPower
     if (totalPower .eq. 0.0)then
        PRINT *, 'Neither surface nor atmosphere will emitt photons since total power is 0. Not a valid solution'
     end if
     totalFlux=totalPower/((xPosition(nx+1)-xPosition(1))*(yPosition(ny+1)-yPosition(1))*(1000**2))  ! We want the units to be [Wm^-2] but the x and y positions are in km
!PRINT *, 'totalPower=', totalPower, ' totalFlux=', totalFlux, ' totalArea=', (xPosition(nx+1)-xPosition(1))*(yPosition(ny+1)-yPosition(1))  
     if (atmsPower .eq. 0.0)then
         atmsPhotons=0
         atmsColumn_photons(:,:)=0
     else   
        atmsPhotons=ceiling(totalPhotons * atmsPower / totalPower)
        atmsColumn_photons(:,:)=floor(atmsPhotons*atmsColumn_power(:,:)/atmsPower)
     end if
  end subroutine emission_weighting

end module monteCarloIllumination
