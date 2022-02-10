module prizmo_self_shielding
	!!BEGIN_SELF_SHIELDING_INTERPOLATION_VARS
    ! >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
    ! NOTE: This block is auto-generated
    ! WHEN: 2020-12-15 15:59:15
    ! CHANGESET: xxxxxxx
    ! URL:
    ! BY: picogna@errc1

    ! CO variables
    integer,parameter::self_shielding_n_CO_NH2=100
    integer,parameter::self_shielding_n_CO_NCO=100
    real*8::self_shielding_xdata_CO(self_shielding_n_CO_NH2)
    real*8::self_shielding_ydata_CO(self_shielding_n_CO_NH2)
    real*8::self_shielding_data_CO(self_shielding_n_CO_NH2, self_shielding_n_CO_NCO)
    real*8::xmin_CO, xfact_CO, invdx_CO, ymin_CO, yfact_CO, invdy_CO

    ! <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
	!!END_SELF_SHIELDING_INTERPOLATION_VARS

contains

	! ********************
	! load self-shielding table, i.e. regular grid in logspace
	! xvar = log10(H2 column density, 1/cm2)
	! yvar = log10(CO column density, 1/cm2)
	! result is attenuation factor due to self shielding, see \Theta in eqn.2 here
	! https://www.aanda.org/articles/aa/pdf/2009/32/aa12129-09.pdf
	subroutine load_self_shielding_CO()
		use prizmo_commons
		use prizmo_fit
		implicit none

		call load_data_2d(runtime_folder//"self_shielding_CO.dat", self_shielding_data_CO(:, :), &
		self_shielding_xdata_CO(:), self_shielding_n_CO_NCO, xmin_CO, xfact_CO, invdx_CO, &
		self_shielding_ydata_CO(:), self_shielding_n_CO_NH2, ymin_CO, yfact_CO, invdy_CO)

	end subroutine load_self_shielding_CO

	! ********************
	! 2D linear interpolation to get attenuation factor due to self-shielding
	! NH2: H2 column density, 1/cm2
	! NCO: CO column density, 1/cm2
	function get_self_shielding_CO(NH2, NCO) result(f)
		use prizmo_fit
		implicit none
		real*8,intent(in)::NH2, NCO
		real*8::v0, v1, f

		! compute column density
		v0 = log10(NH2 + 1d-40)
		v1 = log10(NCO + 1d-40)

		! we approximate large H2 columns density to full shielding
		if(v0 >= self_shielding_xdata_CO(self_shielding_n_CO_NH2)) then
			f = 0d0
			return
		end if

		! we approximate large CO columns density to full shielding
		if(v1 >= self_shielding_ydata_CO(self_shielding_n_CO_NCO)) then
			f = 0d0
			return
		end if

		! for smaller colum density we assume to have constant
		! values from the last available value
		v0 = max(v0, self_shielding_xdata_CO(1))
		v1 = max(v1, self_shielding_ydata_CO(1))

		f = 1e1**interp_2d(v0, v1, self_shielding_data_CO(:, :), &
			xmin_CO, xfact_CO, invdx_CO, ymin_CO, yfact_CO, invdy_CO)

	end function get_self_shielding_CO


	! *****************************
	! H2 self shielding
	function get_self_shielding_H2(NH2, Tgas) result(f)
		implicit none
		real*8,intent(in)::NH2, Tgas
		real*8::f

		!f = get_self_shielding_H2_DB96(NH2, Tgas)
		f = get_self_shielding_H2_R14(NH2, Tgas)

	end function get_self_shielding_H2


	! *****************************
	! H2 self shielding, Draine Bertoldi, 3.11 here
	! https://arxiv.org/abs/1403.6155
	function get_self_shielding_H2_DB96(NH2, Tgas) result(f)
		use prizmo_commons
		implicit none
		real*8,intent(in)::NH2, Tgas
		real*8::f, x, omega_H2, a, sq1x
		real,parameter::b5 = b_line / 1d5

		x = NH2 / 5d14
		omega_H2 = 0.035
		a = 2.
		sq1x = sqrt(1d0 + x)

		f = (1d0 - omega_H2)  / (1d0 + x / b5)**a + omega_H2 / sq1x &
		  * exp(-8.5d-4 * sq1x)


	end function get_self_shielding_H2_DB96

	! *****************************
	! H2 self shielding from eqn. 3.12 here
	! https://arxiv.org/abs/1403.6155
	function get_self_shielding_H2_R14(NH2, Tgas) result(f)
		use prizmo_commons
		implicit none
		real*8,intent(in)::NH2, Tgas
		real*8::f, x, sq1x, omega_H2, a, Ncrit
		real,parameter::b5 = b_line / 1d5

		omega_H2 = 0.013 * (1d0 + (Tgas / 2.7d3)**1.3)**(1d0 / 1.3) &
		* exp(-(Tgas / 3.9d3)**14.6)

		if(Tgas < 3d3) then
			a = 1.4d0
			Ncrit = 1.3d14 * (1d0 + (Tgas / 6d2)**0.8)
		elseif(Tgas > 4d3) then
			a = 1.1d0
			Ncrit = 2d14
		else
			a  = (Tgas / 4.5d3)**(-0.8)
			Ncrit = 1d14 * (Tgas / 4.76d3)**(-3.8)
		end if

		x = NH2 / Ncrit
		sq1x = sqrt(1d0 + x)

		f = (1d0 - omega_H2) / (1d0 + x / b5)**a * exp(-5d-7 * (1d0 + x)) &
		+ omega_H2 / sq1x * exp(-8.5d-4 * sq1x)

	end function get_self_shielding_H2_R14

end module prizmo_self_shielding