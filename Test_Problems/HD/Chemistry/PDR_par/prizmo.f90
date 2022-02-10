module prizmo_main

  !!BEGIN_USER_COMMONS
    ! >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
    ! NOTE: This block is auto-generated
    ! WHEN: 2020-12-15 15:59:15
    ! CHANGESET: xxxxxxx
    ! URL:
    ! BY: picogna@errc1

    ! number of species
    integer,parameter::prizmo_nmols=31

    ! number of reactions
    integer,parameter::prizmo_nrea=289

    ! number of energy bins
    integer,parameter::prizmo_nphoto=1000

    ! species indexes
    integer,parameter::prizmo_idx_H=1
    integer,parameter::prizmo_idx_CH=2
    integer,parameter::prizmo_idx_C=3
    integer,parameter::prizmo_idx_H2=4
    integer,parameter::prizmo_idx_CH3=5
    integer,parameter::prizmo_idx_CH2=6
    integer,parameter::prizmo_idx_CH4=7
    integer,parameter::prizmo_idx_OH=8
    integer,parameter::prizmo_idx_O=9
    integer,parameter::prizmo_idx_H2O=10
    integer,parameter::prizmo_idx_CO=11
    integer,parameter::prizmo_idx_O2=12
    integer,parameter::prizmo_idx_CH2j=13
    integer,parameter::prizmo_idx_CHj=14
    integer,parameter::prizmo_idx_CH3j=15
    integer,parameter::prizmo_idx_Hej=16
    integer,parameter::prizmo_idx_He=17
    integer,parameter::prizmo_idx_Hj=18
    integer,parameter::prizmo_idx_Cj=19
    integer,parameter::prizmo_idx_Oj=20
    integer,parameter::prizmo_idx_H2j=21
    integer,parameter::prizmo_idx_COj=22
    integer,parameter::prizmo_idx_E=23
    integer,parameter::prizmo_idx_H3j=24
    integer,parameter::prizmo_idx_CH4j=25
    integer,parameter::prizmo_idx_OHj=26
    integer,parameter::prizmo_idx_CH5j=27
    integer,parameter::prizmo_idx_H2Oj=28
    integer,parameter::prizmo_idx_H3Oj=29
    integer,parameter::prizmo_idx_HCOj=30
    integer,parameter::prizmo_idx_O2j=31
    integer,parameter::prizmo_idx_H2_photodissociation=258
    integer,parameter::prizmo_idx_CO_photodissociation=259
    integer,parameter::prizmo_idx_C_photoionization=263

    ! <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
  !!END_USER_COMMONS

contains
  !************************
  !evolve chemistry for a time-step dt (s)
  ! n(:) are species number densities
  subroutine prizmo(n, Tgas, jflux, dt)
    use prizmo_commons, only: nmols, nphoto, idx_E, kall
    use prizmo_ode
    use prizmo_rates_photo
    use prizmo_utils
    use prizmo_heating_photo
    implicit none
    real*8,intent(inout)::n(nmols), Tgas
    real*8,intent(in)::dt, jflux(nphoto)

    ! compute electrons to ensure neutral charge
    n(idx_E) = get_electrons(n(:))

    ! compute photochemical rates
    call compute_rates_photo(n(:), Tgas, jflux(:))

    ! precompute photo heating factors
    call pre_integrate_photoheating(jflux(:))

    ! advance chemistry by a time-step
    call dochem(n(:), Tgas, jflux(:), dt)

  end subroutine prizmo

  ! *************************
  function prizmo_get_H_nuclei(n) result(y)
    use prizmo_commons
    use prizmo_utils
    implicit none
    real*8,intent(in)::n(nmols)
    real*8::y

    y = get_Hnuclei(n)

  end function prizmo_get_H_nuclei

  ! *************************
  function prizmo_get_C_nuclei(n) result(y)
    use prizmo_commons
    use prizmo_utils
    implicit none
    real*8,intent(in)::n(nmols)
    real*8::y

    y = get_Cnuclei(n)

  end function prizmo_get_C_nuclei

  ! ************************
  subroutine prizmo_test_jacobian_c1(x, Tgas, jflux)
    use prizmo_commons
    use prizmo_rates_photo
    use prizmo_heating_photo
    use prizmo_rates_evaluate_once
    use prizmo_ode
    implicit none
    real*8,intent(in)::x(nmols), jflux(nphoto), Tgas
    real*8::n(nmols+1), dx(nmols+1), dh, tt
    integer::i,j,k

    jflux_arg = jflux

    ! compute photochemical rates
    call compute_rates_photo(x(:), Tgas, jflux(:))

    ! precompute photo heating factors
    call pre_integrate_photoheating(jflux(:))

    ! precompute evaluate once rates
    call init_evaluate_once()

    open(44, file="jac.dat", status="replace")
    do i=1,nmols+1
      n(1:nmols) = x(:)
      n(nmols+1) = Tgas
      dh = n(i) * 1d-6
      do k=-100,100
        n(1:nmols) = x(:)
        n(nmols+1) = Tgas
        tt = 0d0
        n(i) = n(i) + k * dh
        call fex(nmols+1, tt, n(:), dx(:))
        do j=1,nmols+1
          write(44, '(3I8,99E21.12e3)') i, j, k, n(i), dx(j)
        end do
        write(44, '(3I8,99E21.12e3)') i, nmols+2, k, n(i), prizmo_get_cooling(n(1:nmols), n(idx_Tgas), jflux(:))
        write(44, '(3I8,99E21.12e3)') i, nmols+3, k, n(i), prizmo_get_heating(n(1:nmols), n(idx_Tgas), jflux(:))
      end do
    end do
    close(44)

  end subroutine

  ! *************************
  ! find temperature equilibrium, i.e. Tgas so that heating=cooling
  function prizmo_find_equilibrium_temperature(n, jflux) result(Tgas)
    use prizmo_commons
    use prizmo_rates_photo
    use prizmo_heating_photo
    use prizmo_rates_evaluate_once
    implicit none
    real*8,intent(in)::n(nmols), jflux(nphoto)
    real*8::Tgas, xL, xR, fL, fR, x, f, eps, Tgas_error

    Tgas = 1d2

    ! compute photochemical rates
    call compute_rates_photo(n(:), Tgas, jflux(:))

    ! precompute photo heating factors
    call pre_integrate_photoheating(jflux(:))

    ! precompute evaluate once rates
    call init_evaluate_once()

    ! convergence tolerance for temperature
    eps = 1d-4

    Tgas_error = -1d0

    ! set initial values
    xL = Tgas_min
    xR = Tgas_max

    ! compute cooling-heating at values
    fL = prizmo_get_cooling(n(:), xL, jflux(:)) - prizmo_get_heating(n(:), xL, jflux(:))
    fR = prizmo_get_cooling(n(:), xR, jflux(:)) - prizmo_get_heating(n(:), xR, jflux(:))

    ! check that signs are different for bisection
    if(fL * fR > 0d0) then
       print *, "WARNING: same sign in prizmo_find_equilibrium_temperature bisection"
       print *, xL, xR, fL, fR
       Tgas = Tgas_error
       print *, " returning Tgas=", Tgas
       return
    end if

    ! loop to bisect
    do
       x = (xL + xR) /2.

       f = prizmo_get_cooling(n(:), x, jflux(:)) - prizmo_get_heating(n(:), x, jflux(:))

       ! update point if same sign
       if(f*fL > 0) then
          xL = x
          fL = f
       else
          xR = x
          fR = f
       end if

       ! loop until convergence
       if(abs(xL - xR) < eps) then
          exit
       end if

    end do

    Tgas = x

  end function prizmo_find_equilibrium_temperature

  ! ******************
  subroutine prizmo_set_jflux(jflux)
    use prizmo_commons
    use prizmo_ode
    implicit none
    real*8,intent(in)::jflux(nphoto)

    jflux_arg(:) = jflux(:)

  end subroutine prizmo_set_jflux

  ! **********************
  function prizmo_fex(x, Tgas) result(dx)
    use prizmo_commons
    use prizmo_ode
    implicit none
    real*8,intent(in)::x(nmols), Tgas
    real*8::n(nmols+1), dx(nmols+1)
    real*8::tt

    tt = 0d0
    n(1:nmols) = x(:)
    n(nmols+1) = Tgas

    call fex(nmols+1, tt, n(:), dx(:))

  end function prizmo_fex
  ! **********************

  function prizmo_get_timescale(n, Tgas) result(dt)
    use prizmo_commons
    use prizmo_ode
    implicit none
    real*8,intent(inout)::n(nmols), Tgas
    real*8::dt

    dt = get_timescale(n(:), Tgas)

  end function prizmo_get_timescale

  ! ************************
  subroutine prizmo_set_debug(val)
    use prizmo_commons
    implicit none
    integer,intent(in):: val

    debug = val

  end subroutine prizmo_set_debug

  ! *******************
  ! initialize PRIZMO
  subroutine prizmo_init()
    use prizmo_commons
    use prizmo_cooling_CO
    use prizmo_cooling_H2O
    use prizmo_self_shielding
    use prizmo_xsecs
    use prizmo_rates
    use prizmo_attenuation
    use prizmo_heating_photo
    use prizmo_tdust
    use prizmo_emission
    use prizmo_rates_evaluate_once
    use prizmo_heating_photoelectric
    use prizmo_H2_dust
    implicit none

    ! service variable, ignore for standard use
    debug = 0

    ! chemistry mode, when -1 chemistry kall = 0, i.e. chemistry off
    chemistry_mode = 0

    ! set cooling mode, zero is default to have all the relevant coolings on
    cooling_mode = 0

    ! set heating mode, zero is default to have all the relevant heatings on
    heating_mode = 0

    ! Tdust calculation flag, when 1 Tdust=20K, 2 is Hocuck Av function, 3 is Tdust=Tgas
    tdust_mode = 0

    ! beta escape for emission lines, compute if 0, ignore if -1
    beta_escape_mode = 0

    ! set default rates to zero
    kall(:) = 0d0

    ! default temperature limits imposed by user, K
    Tgas_min_forced = -1d99
    Tgas_max_forced = 1d99

    ! initialize photochemical xsecs
    call load_xsecs_all()

    ! load CO cooling tables
    call load_cooling_CO()

    ! load H2O cooling tables
    call load_cooling_H2O()

    ! load self shielding tables
    call load_self_shielding_CO()

    ! load data for dust temperature calculation with bisection
    call load_tdust_data()

    ! load molecular data for emission
    call load_emission_data()

    ! load factors for photoelectric heating
    call load_photoelectric_data()

    ! load efficiency tables for H2 formation on dust
    call load_H2_dust_table()

    ! default emission array
    emission_array_energy(:) = 0d0
    emission_array_flux(:) = 0d0

    !!BEGIN_USER_VARIABLES_DEFAULT
    ! >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
    ! NOTE: This block is auto-generated
    ! WHEN: 2020-12-15 15:59:15
    ! CHANGESET: xxxxxxx
    ! URL:
    ! BY: picogna@errc1

    ! init user variables to default
    variable_Av = 0d0
    variable_G0 = 0d0
    variable_crflux = 0d0
    variable_NCO_incoming = 0d0
    variable_NCO_escaping = 0d0
    variable_NH2_incoming = 0d0
    variable_NH2_escaping = 0d0
    variable_NH2O_escaping = 0d0

    ! <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    !!END_USER_VARIABLES_DEFAULT

    ! interpolate rates to save time at runtime
    call interpolate_rates()

    ! check if interpolation is done correctly
    call test_rate_interpolation()

    ! load dust opacity from file
    call load_dust_opacity(runtime_folder//"dust_opacity.dat")

    ! load heating thresholds, eV
    call load_heating_thresholds(runtime_folder//"heating_threshold.dat")

    print *, "init done!"

  end subroutine prizmo_init

  ! *******************
  ! print recap to screen with commons quantities
  subroutine prizmo_recap()
    use prizmo_commons
    character(len=20)::fmti,fmtr

    fmti = "(a43,99I17)"
    fmtr = "(a43,99E17.8e3)"

    print fmti, "number of species                         ", nmols
    print fmti, "number of reactions                       ", nrea
    print fmti, "number of photo bins                      ", nphoto
    print fmtr, "min temperature, K                        ", Tgas_min
    print fmtr, "max temperature, K                        ", Tgas_max
    print fmtr, "dust-to-gas ratio                         ", d2g
    print fmtr, "dust bulk density, g/cm3                  ", dust_rho_bulk
    print fmtr, "dust min size, cm                         ", dust_amin
    print fmtr, "dust max size, cm                         ", dust_amax
    print fmtr, "dust exponential, cm                      ", dust_pexp
    print fmtr, "line velocity b-factor, cm/s              ", dust_pexp
    print fmtr, "velocity gradient escape probability, 1/s ", dvdz
    print fmtr, "ortho-para ratio H2                       ", opratio_H2

  end subroutine prizmo_recap

  ! *******************
  function prizmo_get_H2_dust_n(Tgas, Tdust, n) result(k)
    use prizmo_commons
    use prizmo_H2_dust
    implicit none
    real*8,intent(in)::Tgas, Tdust, n(nmols)
    real*8::k

    k = get_H2_dust_n(Tgas, Tdust, n(:))

  end function prizmo_get_H2_dust_n

  ! *******************
  ! save emission array to file, eV, erg/s/cm3
  subroutine prizmo_save_emission_array_at(unit, xvar, n, Tgas)
    use prizmo_commons
    use prizmo_emission
    implicit none
    real*8,intent(in)::xvar, n(nmols), Tgas
    real*8::emission(nphoto)
    integer,intent(in)::unit
    integer::i
    character(len=80)::fname

    emission_array_flux(:) = 0d0  ! this is for the lines
    emission(:) = 0d0  ! this is binned on the photobins
    call add_emission(emission(:), n(:), Tgas)

    ! emission_array_flux is a common in prizmo_emission
    do i=1,ntransitions
       write(unit, '(3E17.8e3,a50)') xvar, emission_array_energy(i), emission_array_flux(i), trim(emission_array_names(i))
    end do
    write(unit, *)

    ! write file where emission array is saved
    inquire(unit=unit, name=fname)
    print *, "emission array saved to "//trim(fname)

  end subroutine prizmo_save_emission_array_at

  ! *********************
  ! define forced temperature min, K
  subroutine prizmo_set_Tgas_min_forced(arg)
    use prizmo_commons
    implicit none
    real*8,intent(in)::arg

    Tgas_min_forced = arg

  end subroutine prizmo_set_Tgas_min_forced

  ! *********************
  ! define forced temperature max, K
  subroutine prizmo_set_Tgas_max_forced(arg)
    use prizmo_commons
    implicit none
    real*8,intent(in)::arg

    Tgas_max_forced = arg

  end subroutine prizmo_set_Tgas_max_forced

  ! ********************
  ! get cooling, erg/s/cm-3
  function prizmo_get_cooling(n, Tgas, jflux) result(cool)
    use prizmo_commons
    use prizmo_cooling
    use prizmo_tdust
    implicit none
    real*8,intent(in)::n(nmols), Tgas, jflux(nphoto)
    real*8::cool, Tdust

    Tdust = get_Tdust(n(:), Tgas, jflux(:))
    cool = cooling(n(:), Tgas, Tdust, jflux(:))

  end function prizmo_get_cooling

  ! ********************
  ! get heating, erg/s/cm-3
  function prizmo_get_heating(n, Tgas, jflux) result(heat)
    use prizmo_commons
    use prizmo_heating
    use prizmo_tdust
    implicit none
    real*8,intent(in)::n(nmols), Tgas, jflux(nphoto)
    real*8::heat, Tdust

    Tdust = get_Tdust(n(:), Tgas, jflux(:))
    heat = heating(n(:), Tgas, Tdust, jflux(:))

  end function prizmo_get_heating

  ! *******************
  ! save cooling array
  subroutine prizmo_save_cooling_array_profile_at(unit, xvar, n, Tmin, Tmax, steps, jflux)
    use prizmo_commons
    use prizmo_cooling
    use prizmo_heating
    use prizmo_rates
    use prizmo_tdust
    use prizmo_rates_evaluate_once
    use prizmo_rates_photo
    use prizmo_heating_photo
    implicit none
    integer,intent(in)::steps
    real*8,intent(in)::n(nmols), Tmin, Tmax, jflux(nphoto), xvar
    real*8::Tgas, Tdust
    integer::i, unit
    character(len=80)::fname

    call init_evaluate_once()

    ! precompute photo heating factors
    call pre_integrate_photoheating(jflux(:))

    do i=1,steps
       Tgas = 1e1**((i-1) * (log10(Tmax) - log10(Tmin)) / (steps - 1) &
            + log10(Tmin))
       Tgas = min(max(Tgas, Tgas_min), Tgas_max)

       Tdust = get_Tdust(n(:), Tgas, jflux(:))

       ! compute non-photochemical rates
       call compute_rates(n(:), Tgas, Tdust, jflux(:))

       ! compute photochemical rates
       call compute_rates_photo(n(:), Tgas, jflux(:))

       write(unit, '(99E17.8e3)') xvar, Tgas, &
            get_cooling_array(n(:), Tgas, Tdust, jflux(:)), &
            get_heating_array(n(:), Tgas, Tdust, jflux(:))
    end do
    write(unit, *)

    inquire(unit=unit, name=fname)
    print *, "cooling array function saved to "//trim(fname)

  end subroutine prizmo_save_cooling_array_profile_at

  ! *******************
  ! save cooling array
  subroutine prizmo_save_cooling_array_at(unit, xvar, n, Tgas, jflux)
    use prizmo_commons
    use prizmo_cooling
    use prizmo_heating
    use prizmo_rates
    use prizmo_tdust
    use prizmo_rates_evaluate_once
    use prizmo_rates_photo
    use prizmo_heating_photo
    implicit none
    real*8,intent(in)::n(nmols), Tgas, jflux(nphoto), xvar
    integer,intent(in)::unit
    real*8::Tdust
    character(len=80)::fname

    call init_evaluate_once()

    ! precompute photo heating factors
    call pre_integrate_photoheating(jflux(:))

    Tdust = get_Tdust(n(:), Tgas, jflux(:))

    ! compute non-photochemical rates
    call compute_rates(n(:), Tgas, Tdust, jflux(:))

    ! compute photochemical rates
    call compute_rates_photo(n(:), Tgas, jflux(:))

    write(unit, '(99E17.8e3)') xvar, get_cooling_array(n(:), Tgas, Tdust, jflux(:)), &
         get_heating_array(n(:), Tgas, Tdust, jflux(:))

    inquire(unit=unit, name=fname)
    print *, "cooling array function saved to "//trim(fname)

  end subroutine prizmo_save_cooling_array_at

  ! *******************
  function prizmo_get_cooling_array(n, Tgas, Tdust, jflux) result(cooling_array)
    use prizmo_commons
    use prizmo_cooling
    implicit none
    real*8,intent(in)::n(nmols), Tgas, Tdust, jflux(nphoto)
    real*8::cooling_array(cooling_number)

    cooling_array(:) = get_cooling_array(n(:), Tgas, Tdust, jflux(:))

  end function prizmo_get_cooling_array

  ! *******************
  function prizmo_get_heating_array(n, Tgas, Tdust, jflux) result(heating_array)
    use prizmo_commons
    use prizmo_heating
    implicit none
    real*8,intent(in)::n(nmols), Tgas, Tdust, jflux(nphoto)
    real*8::heating_array(heating_number)

    heating_array(:) = get_heating_array(n(:), Tgas, Tdust, jflux(:))

  end function prizmo_get_heating_array


  ! *******************
  subroutine prizmo_save_cooling_function(unit, n, Tmin, Tmax, steps, jflux)
    use prizmo_commons
    use prizmo_cooling
    use prizmo_heating
    use prizmo_rates
    use prizmo_tdust
    use prizmo_rates_evaluate_once
    use prizmo_rates_photo
    use prizmo_heating_photo
    implicit none
    real*8,intent(in)::n(nmols), Tmin, Tmax, jflux(nphoto)
    integer,intent(in)::steps
    real*8::Tgas, Tdust
    integer::i, unit
    character(len=80)::fname

    call init_evaluate_once()

    ! precompute photo heating factors
    call pre_integrate_photoheating(jflux(:))

    do i=1,steps
       Tgas = 1e1**((i-1) * (log10(Tmax) - log10(Tmin)) / (steps - 1) + log10(Tmin))
       Tgas = min(max(Tgas, Tgas_min), Tgas_max)

       Tdust = get_Tdust(n(:), Tgas, jflux(:))

       ! compute non-photochemical rates
       call compute_rates(n(:), Tgas, Tdust, jflux(:))

       ! compute photochemical rates
       call compute_rates_photo(n(:), Tgas, jflux(:))

       write(unit, '(99E17.8e3)') Tgas, cooling(n(:), Tgas, Tdust, jflux(:)), &
            heating(n(:), Tgas, Tdust, jflux(:))
    end do
    write(unit, *)

    inquire(unit=unit, name=fname)
    print *, "cooling function saved to "//trim(fname)

  end subroutine prizmo_save_cooling_function

  ! *******************
  ! alias to return H2 shielding, using eqn. 3.12 here
  ! https://arxiv.org/abs/1403.6155
  function prizmo_get_self_shielding_H2(NH2, Tgas) result(shield)
    use prizmo_self_shielding
    implicit none
    real*8,intent(in)::NH2, Tgas
    real*8::shield

    shield = get_self_shielding_H2(NH2, Tgas)

  end function prizmo_get_self_shielding_H2

  ! *******************
  function prizmo_get_rates(n, Tgas, jflux) result(k)
    use prizmo_commons
    use prizmo_rates
    use prizmo_rates_photo
    use prizmo_tdust
    use prizmo_rates_evaluate_once
    implicit none
    real*8,intent(in)::n(nmols), Tgas, jflux(nphoto)
    real*8::Tdust, k(nrea)

    Tdust = get_Tdust(n(:), Tgas, jflux(:))

    call compute_rates_photo(n(:), Tgas, jflux(:))
    call init_evaluate_once()
    call compute_rates(n(:), Tgas, Tdust, jflux(:))

    k(:) = kall(:)

  end function prizmo_get_rates

  ! *******************
  function prizmo_get_Tdust(n, Tgas, jflux) result(Tdust)
    use prizmo_commons
    use prizmo_tdust
    implicit none
    real*8,intent(in)::n(nmols), Tgas, jflux(nphoto)
    real*8::Tdust

    Tdust = get_Tdust(n(:), Tgas, jflux(:))

  end function prizmo_get_Tdust

  ! *****************
  function prizmo_get_electrons(n) result(ne)
    use prizmo_utils
    use prizmo_commons
    implicit none
    real*8,intent(in)::n(nmols)
    real*8::ne

    ne = get_electrons(n(:))

  end function prizmo_get_electrons

  ! *****************
  function prizmo_get_species_mass() result(masses)
    use prizmo_commons
    real*8::masses(nmols)

    masses(:) = mass(:)

  end function prizmo_get_species_mass

  ! ******************
  function prizmo_get_rho(n) result(rho)
    use prizmo_commons
    use prizmo_utils
    implicit none
    real*8::n(nmols)
    real*8::rho

    rho = get_rho(n(:))

  end function prizmo_get_rho

  ! *************************
  ! set cooling mode, zero is default, 1 is SML97 cooling only, -1 is turned off
  subroutine prizmo_set_cooling_mode(mode)
    use prizmo_commons
    implicit none
    integer,intent(in)::mode

    cooling_mode = mode

  end subroutine prizmo_set_cooling_mode

  ! *************************
  ! set heating mode, zero is default, 1 is CR heating only, -1 is turned off
  subroutine prizmo_set_heating_mode(mode)
    use prizmo_commons
    implicit none
    integer,intent(in)::mode

    heating_mode = mode

  end subroutine prizmo_set_heating_mode

  ! *************************
  ! set Tdust mode, zero is default, 1 is 20K, 2 is Hocuck Av-dependent, 3 is Tdust=Tgas
  subroutine prizmo_set_tdust_mode(mode)
    use prizmo_commons
    implicit none
    integer,intent(in)::mode

    tdust_mode = mode

  end subroutine prizmo_set_tdust_mode

  ! *************************
  ! set chemistry mode, zero is default, -1 is turned off
  subroutine prizmo_set_chemistry_mode(mode)
    use prizmo_commons
    implicit none
    integer,intent(in)::mode

    cooling_mode = mode

  end subroutine prizmo_set_chemistry_mode

  ! *************************
  ! set emission beta escape probability mode, zero is default, -1 is turned off
  subroutine prizmo_set_beta_escape_mode(mode)
    use prizmo_commons
    implicit none
    integer,intent(in)::mode

    beta_escape_mode = mode

  end subroutine prizmo_set_beta_escape_mode

  ! *******************************
  ! print first nbest verbatim sorted by reaction fluxes
  subroutine prizmo_print_sorted_fluxes(n, Tgas, jflux, nbest)
    use prizmo_commons
    use prizmo_fluxes
    implicit none
    real*8,intent(in)::n(nmols), Tgas, jflux(nphoto)
    integer,intent(in)::nbest

    call print_sorted_fluxes(n(:), Tgas, Jflux(:), nbest)

  end subroutine prizmo_print_sorted_fluxes

  ! *******************************
  ! print first nbest verbatim sorted by reaction fluxes
  subroutine prizmo_print_sorted_fluxes_species(n, Tgas, jflux, nbest, species)
    use prizmo_commons
    use prizmo_fluxes
    implicit none
    real*8,intent(in)::n(nmols), Tgas, jflux(nphoto)
    integer,intent(in)::nbest, species(:)

    call print_sorted_fluxes_species(n(:), Tgas, Jflux(:), nbest, species(:))

  end subroutine prizmo_print_sorted_fluxes_species

  ! ***************************
  ! get sorted reaction fluxes
  function prizmo_get_sorted_fluxes(n, Tgas, jflux) result(fluxes)
    use prizmo_commons
    use prizmo_fluxes
    implicit none
    real*8,intent(in)::n(nmols), Tgas, jflux(nphoto)
    real*8::fluxes(nrea)

    fluxes(:) = get_sorted_fluxes(n(:), Tgas, jflux(:))

  end function prizmo_get_sorted_fluxes

  ! ***************************
  ! get reaction fluxes
  function prizmo_get_fluxes(n, Tgas, jflux) result(fluxes)
    use prizmo_commons
    use prizmo_fluxes
    implicit none
    real*8,intent(in)::n(nmols), Tgas, jflux(nphoto)
    real*8::fluxes(nrea)

    fluxes(:) = get_fluxes(n(:), Tgas, jflux(:))

  end function prizmo_get_fluxes

  ! ************************
  ! return time since epoch in milliseconds
  function prizmo_get_utime() result(utime)
    implicit none
    real*4::utime
    integer::values(8)

    call date_and_time(values=values)

    uTime = (values(5)) * 6e1         ! Hours to minutes
    uTime = (uTime + values(6)) * 6e1 ! Minutes to seconds
    uTime = (uTime + values(7)) * 1e3 ! Seconds to milliseconds
    uTime = uTime + values(8)         ! Add milliseconds

  end function prizmo_get_utime

  !!BEGIN_USER_VARIABLES_FUNCTIONS
    ! >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
    ! NOTE: This block is auto-generated
    ! WHEN: 2020-12-15 15:59:15
    ! CHANGESET: xxxxxxx
    ! URL:
    ! BY: picogna@errc1

    ! *************************
    ! user variable VARIABLE_AV initialization function
    subroutine prizmo_set_variable_Av(arg)
        use prizmo_commons, only: variable_Av
        implicit none
        real*8,intent(in)::arg

        variable_Av = arg

    end subroutine prizmo_set_variable_Av

    ! *************************
    ! user variable VARIABLE_G0 initialization function
    subroutine prizmo_set_variable_G0(arg)
        use prizmo_commons, only: variable_G0
        implicit none
        real*8,intent(in)::arg

        variable_G0 = arg

    end subroutine prizmo_set_variable_G0

    ! *************************
    ! user variable VARIABLE_CRFLUX initialization function
    subroutine prizmo_set_variable_crflux(arg)
        use prizmo_commons, only: variable_crflux
        implicit none
        real*8,intent(in)::arg

        variable_crflux = arg

    end subroutine prizmo_set_variable_crflux

    ! *************************
    ! user variable VARIABLE_NCO_INCOMING initialization function
    subroutine prizmo_set_variable_NCO_incoming(arg)
        use prizmo_commons, only: variable_NCO_incoming
        implicit none
        real*8,intent(in)::arg

        variable_NCO_incoming = arg

    end subroutine prizmo_set_variable_NCO_incoming

    ! *************************
    ! user variable VARIABLE_NCO_ESCAPING initialization function
    subroutine prizmo_set_variable_NCO_escaping(arg)
        use prizmo_commons, only: variable_NCO_escaping
        implicit none
        real*8,intent(in)::arg

        variable_NCO_escaping = arg

    end subroutine prizmo_set_variable_NCO_escaping

    ! *************************
    ! user variable VARIABLE_NH2_INCOMING initialization function
    subroutine prizmo_set_variable_NH2_incoming(arg)
        use prizmo_commons, only: variable_NH2_incoming
        implicit none
        real*8,intent(in)::arg

        variable_NH2_incoming = arg

    end subroutine prizmo_set_variable_NH2_incoming

    ! *************************
    ! user variable VARIABLE_NH2_ESCAPING initialization function
    subroutine prizmo_set_variable_NH2_escaping(arg)
        use prizmo_commons, only: variable_NH2_escaping
        implicit none
        real*8,intent(in)::arg

        variable_NH2_escaping = arg

    end subroutine prizmo_set_variable_NH2_escaping

    ! *************************
    ! user variable VARIABLE_NH2O_ESCAPING initialization function
    subroutine prizmo_set_variable_NH2O_escaping(arg)
        use prizmo_commons, only: variable_NH2O_escaping
        implicit none
        real*8,intent(in)::arg

        variable_NH2O_escaping = arg

    end subroutine prizmo_set_variable_NH2O_escaping

    ! <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
  !!END_USER_VARIABLES_FUNCTIONS

end module prizmo_main