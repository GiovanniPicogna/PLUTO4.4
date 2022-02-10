module prizmo_rates
	use prizmo_commons
	integer,parameter::ngrid=10000
	real*8,parameter::logTmin=log10(1d0), logTmax=log10(1d8)
	real*8::krate_grid(nrea, ngrid), Tgas_grid(ngrid)
	real*8::grid_idlogT
	real*8::krate_dgrid(nrea, ngrid)

contains

	! *******************
	! interpolate rates
	subroutine interpolate_rates()
		use prizmo_tdust
		use prizmo_rates_interpolable
		use prizmo_rates_evaluate_once
		implicit none
		real*8::n(nmols), Tgas, Tdust, jflux(nphoto)
		integer::j

		print *, "Interpolating rates..."

		n(:) = 1d-40
		jflux(:) = 0d0
		krate_grid(:, :) = 0d0

		! init evaluate once to avoid errors
		! however, these rates are evaluated every time dochem is called
		call init_evaluate_once()

		do j=1,ngrid
			Tgas = 1d1**((j - 1) * (logTmax - logTmin) / (ngrid - 1) + logTmin)
			Tdust = Tgas !get_Tdust(n(:), Tgas, jflux(:))
			kall(:) = 0d0

			! evaluate rates at given temperature
			call evaluate_interpolable(n(:), Tgas, Tdust)

			! check negative values
			if(minval(kall) < 0d0) then
				print *, "ERROR: negative rates when interpolating at Tgas=", Tgas
				stop
			end if

			Tgas_grid(j) = log10(Tgas)
			krate_grid(:, j) = log10(kall(:) + 1d-40)
		end do

		do j=1,nrea
			krate_dgrid(j, 1:ngrid-1) = krate_grid(j, 2:ngrid) - krate_grid(j, 1:ngrid-1)
			krate_dgrid(j, ngrid) = 0d0
			if(maxval(krate_grid(j, :)) > log10(1d-4)) then
				print *, "WARNING: rate > 1", j, 1d1**maxval(krate_grid(j, :))
			end if
		end do

		! store inverse of grid spacing for later use
		grid_idlogT = 1d0 / (Tgas_grid(2) - Tgas_grid(1))

	end subroutine interpolate_rates

	! *****************
	! test if interpolation matches
	subroutine test_rate_interpolation()
		use prizmo_tdust
		use prizmo_rates_evaluate_once
		implicit none
		integer::j, jmax, i
		real*8::Tgas, Tdust, kloc(nrea), n(nmols), err
		real*8::jflux(nphoto)

		! number of temperature point where to test the rates
		jmax = 100

		jflux(:) = 0d0
		n(:) = 1d-40

		print *, "Testing rate interpolation..."
		print *, "skipping"
		return

		! init evaluate once to avoid errors
		! however, these rates are evaluated every time dochem is called
		call init_evaluate_once()

		! loop on temperature
		do j=2,jmax-1
			! temperature
			Tgas = 1d1**((j - 1) * (logTmax - logTmin) / (jmax - 1) + logTmin)
			Tdust = Tgas

			! evaluate rates without interpolation
			call evaluate_interpolable(n(:), Tgas, Tdust)

			! store rates
			kloc(:) = kall(:)

			! evaluate rates using interpolation
			call compute_rates(n(:), Tgas, Tdust, jflux(:))

			! loop on rates to evaluate errror
			do i=1,nrea
				! small rates are ignored
				if(kall(i) < 1d-30 .and. kloc(i) < 1d-30) then
					cycle
				end if

				! relative error
				err = abs(kall(i) - kloc(i)) / kall(i)

				! warning if error
				if(err > 1d-10) then
					print *, "WARNING: test rate interpolation. "
					print '(a5,99a17)', "idx", "err", "kall", "kloc", "Tgas"
					print '(I5,99E17.8e3)', i, err, kall(i), kloc(i), Tgas
				end if
			end do
			!stop
		end do

		print *, "test done"

	end subroutine test_rate_interpolation

	! *****************
	! this is the main call to set the common variable kall(:) that contains the rate coefficients.
	! this function calls the different rate functions depending on the rate type and on
	! the optimization scheme (e.g. evaluate_once, interpolable, not_interpolable, and so on...)
	subroutine compute_rates(n, Tgas_in, Tdust, jflux)
		use prizmo_commons
		use prizmo_self_shielding
		use prizmo_utils
		use prizmo_rates_not_interpolable
		implicit none
		real*8,intent(in)::n(nmols), Tgas_in, Tdust, jflux(nphoto)
		real*8::logTgas, Tgas, fact
		real*8::inv_Tgas, sqrt_Tgas, pre_freeze, stick, rho_dust, inv_Tdust
		real*8::pre_scale, pre_2body, ntot, mu, prev, ndns, invsqrt32
		integer::idx, i
		character(len=max_character_len)::rnames(nrea)

		! chemistry mode -1 is no chemistry
		if(chemistry_mode == -1) then
			kall(:) = 0d0
			return
		end if

		! this check is to avoid strange behaviour when rates are evaluated
		Tgas = min(max(Tgas_in, Tgas_min), Tgas_max)

		! interpolation variables
		logTgas = log10(Tgas)
		idx = (logTgas - logTmin) * (ngrid - 1) / (logTmax - logTmin) + 1
		fact = (logTgas - Tgas_grid(idx)) * grid_idlogT

		!!BEGIN_INTERPOLATE_RATES
    ! >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
    ! NOTE: This block is auto-generated
    ! WHEN: 2020-12-15 15:59:15
    ! CHANGESET: xxxxxxx
    ! URL:
    ! BY: picogna@errc1

    kall(1:94) = 1d1**(krate_dgrid(1:94, idx) * fact + krate_grid(1:94, idx))

    ! <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
		!!END_INTERPOLATE_RATES


		!!BEGIN_EVALUATE_ONCE
    ! >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
    ! NOTE: This block is auto-generated
    ! WHEN: 2020-12-15 15:59:15
    ! CHANGESET: xxxxxxx
    ! URL:
    ! BY: picogna@errc1

    kall(95:287) = krate_evaluate_once(95:287)

    ! <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
		!!END_EVALUATE_ONCE

		! evaluate rates that are not evaluted once and that are not interpolated
		call evaluate_not_interpolable(n(:), Tgas, Tdust, jflux(:))

		kall(:) = kall(:) + 1d-40

		! DEBUG: test rates (uncomment here below)
		! rnames(:) = get_reaction_names()
		! print *, "***************"
		! do i=1,nrea
		! 	if(kall(i) > 1d-4) print '(a16,a30,I8,99E17.8e3)', "rate>0.1!", rnames(i), i, kall(i), Tgas, Tdust
		! 	if(kall(i) < 0d0) print '(a16,a30,I8,99E17.8e3)', "rate<0!", rnames(i), i, kall(i), Tgas, Tdust
		! 	!if(kall(i) < 1d-20) print '(a16,I8,99E17.8e3)', "rate<1e-20!", i, kall(i), Tgas, Tdust
		! end do

	end subroutine compute_rates


end module prizmo_rates