import { ChangeDetectionStrategy, Component, inject, signal, viewChild, DestroyRef } from '@angular/core';
import { LowerCasePipe } from '@angular/common';
import { MatButtonModule } from '@angular/material/button';
import { MatDialogModule, MatDialogRef } from '@angular/material/dialog';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatIcon } from '@angular/material/icon';
import { MatStepper, MatStepperModule } from '@angular/material/stepper';
import { createStepperOrientationSignal } from '@shared/utilities/stepper-orientation/stepper-orientation.util';
import { MatSelectModule } from '@angular/material/select';
import { MatInputModule } from '@angular/material/input';
import { CompanyService } from '@core/service/company/company.service';
import { FormBuilder, ReactiveFormsModule, Validators, AsyncValidatorFn, AbstractControl, ValidationErrors } from '@angular/forms';
import { CompanyTypes, CompanyAdminFormData } from '@shared/types/company-types';
import { OrganizationService } from '@core/service/organization/organization.service';
import { AuthService } from '@core/service/auth/auth.service';
import { switchMap, take, map, forkJoin, timer, of, Observable, catchError } from 'rxjs';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { MatProgressSpinnerModule } from '@angular/material/progress-spinner';
import { CompanyAdminService } from '@core/service/company-admin/company-admin.service';
import { SnackBarService } from '@shared/services/snack-bar/snack-bar.service';
import { LoggerService } from '@shared/services/logger/logger.service';
import { TranslateModule, TranslateService } from '@ngx-translate/core';

@Component({
   selector: 'create-company-dialog',
   templateUrl: './create-company-dialog.html',
   styleUrl: './create-company-dialog.scss',
   imports: [
      MatDialogModule,
      MatButtonModule,
      MatFormFieldModule,
      ReactiveFormsModule,
      MatIcon,
      MatStepperModule,
      MatInputModule,
      MatSelectModule,
      MatProgressSpinnerModule,
      TranslateModule,
      LowerCasePipe,
   ],
   changeDetection: ChangeDetectionStrategy.OnPush,
})
export class CreateCompanyDialog {
   private readonly companyService = inject(CompanyService);
   private readonly organizationService = inject(OrganizationService);
   private readonly authService = inject(AuthService);
   private readonly companyAdminService = inject(CompanyAdminService);
   private readonly snackBarService = inject(SnackBarService);
   private readonly logger = inject(LoggerService);
   private readonly translateService = inject(TranslateService);
   // private readonly dialogData = inject<{ company: CompanyType }>(MAT_DIALOG_DATA);
   protected readonly stepper = viewChild.required(MatStepper);
   private readonly fb = inject(FormBuilder);
   private readonly destroyRef = inject(DestroyRef);

   protected readonly dialogRef = inject(MatDialogRef<CreateCompanyDialog>);

   protected readonly isLoading = signal(false);
   protected readonly error = signal(<string | null>null);

   // Store created company data
   protected readonly createdCompany = signal<{
      uid: string;
      name: string;
      code: string;
      type: CompanyTypes;
      organizationUID: string;
      organizationName: string;
   } | null>(null);

   protected readonly companyForm = this.fb.group({
      name: ['', [Validators.required, Validators.minLength(3), Validators.maxLength(100)]],
      code: ['', [Validators.required, Validators.minLength(1), Validators.maxLength(12)]],
      type: ['', Validators.required],
   });

   protected readonly adminForm = this.fb.group({
      email: ['', {
         validators: [Validators.required, Validators.email],
         asyncValidators: [this.emailAvailabilityValidator()],
      }],
      phoneNumber: ['', [Validators.required, Validators.pattern(/^\d{11}$/)]],
   });

   private emailAvailabilityValidator(): AsyncValidatorFn {
      return (control: AbstractControl): Observable<ValidationErrors | null> => {
         if (!control.value) {
            return of(null);
         }
         const company = this.createdCompany();
         if (!company) {
            return of(null); // Cannot validate without company context yet
         }

         const normalizedEmail = control.value.toLowerCase().trim();

         return timer(500).pipe(
            switchMap(() =>
               this.companyAdminService.isCompanyAdminEmailAvailable$(
                  company.organizationUID,
                  company.uid,
                  normalizedEmail
               )
            ),
            map((isAvailable) => (isAvailable ? null : { emailTaken: true })),
            catchError((err) => {
               this.logger.error('Email availability check failed', err);
               // In case of error, we should probably mark it as taken to be safe,
               // or at least not mark it as valid.
               return of({ emailCheckFailed: true });
            })
         );
      };
   }

   protected readonly companyTypes = signal<CompanyTypes[]>(['Advertising', 'Product', 'Recruitment']);

   protected readonly stepperOrientation = createStepperOrientationSignal(768);

   onNoClick(): void {
      this.dialogRef.close();
   }

   createCompany(): void {
      if (this.companyForm.invalid) {
         this.companyForm.markAllAsTouched();
         return;
      }

      // Clear any existing async validation errors
      const nameControl = this.companyForm.get('name');
      const codeControl = this.companyForm.get('code');
      if (nameControl?.errors) {
         const { nameTaken, ...rest } = nameControl.errors;
         nameControl.setErrors(Object.keys(rest).length ? rest : null);
      }
      if (codeControl?.errors) {
         const { codeTaken, ...rest } = codeControl.errors;
         codeControl.setErrors(Object.keys(rest).length ? rest : null);
      }

      this.isLoading.set(true);
      this.error.set(null);

      const { name, type, code } = this.companyForm.getRawValue();

      // Get current authenticated org admin user to derive organization UID
      const currentUser = this.authService.currentUser();
      if (!currentUser) {
         this.isLoading.set(false);
         this.error.set(this.translateService.instant('errors.userNotAuthenticated'));
         return;
      }
      // Narrow: Only organization or company admins have organization context
      const orgUID = 'organizationUID' in currentUser ? currentUser.organizationUID : undefined;
      if (!orgUID) {
         this.isLoading.set(false);
         this.error.set(this.translateService.instant('errors.organizationContextMissing'));
         return;
      }

      // Validate code and name availability in parallel
      forkJoin({
         codeAvailable: this.companyService.isCompanyCodeAvailable$(orgUID, code!),
         nameAvailable: this.companyService.isCompanyNameAvailable$(orgUID, name!),
      })
         .pipe(
            switchMap(({ codeAvailable, nameAvailable }) => {
               // Check if code is taken
               if (!codeAvailable) {
                  if (codeControl) {
                     codeControl.setErrors({ codeTaken: true });
                     codeControl.markAsTouched();
                  }
                  this.isLoading.set(false);
                  throw new Error('codeTaken');
               }

               // Check if name is taken
               if (!nameAvailable) {
                  if (nameControl) {
                     nameControl.setErrors({ nameTaken: true });
                     nameControl.markAsTouched();
                  }
                  this.isLoading.set(false);
                  throw new Error('nameTaken');
               }

               // Both validations passed, proceed with company creation
               return this.organizationService.getOrganizationById$(orgUID).pipe(take(1));
            }),
            switchMap((org) => {
               if (!org) throw new Error('Organization not found.');
               return this.companyService.createCompanyWithOrganization$(
                  { uid: org.uid, code: org.code, name: org.name },
                  { name: name!, type: type as CompanyTypes, code: code! }
               );
            }),
            takeUntilDestroyed(this.destroyRef)
         )
         .subscribe({
            next: (newId) => {
               this.isLoading.set(false);

               // Store created company data for step 2
               this.organizationService
                  .getOrganizationById$(orgUID)
                  .pipe(
                     take(1),
                     takeUntilDestroyed(this.destroyRef)
                  )
                  .subscribe((org) => {
                     this.createdCompany.set({
                        uid: newId,
                        name: name!,
                        code: code!,
                        type: type as CompanyTypes,
                        organizationUID: orgUID,
                        organizationName: org?.name || '',
                     });
                  });

               this.stepper().next();
            },
            error: (err: unknown) => {
               this.logger.error('Failed to create company', err);
               // Don't show error message for validation errors (they're shown on form controls)
               const errorMessage = err instanceof Error ? err.message : (err as { message?: string })?.message;
               if (errorMessage !== 'codeTaken' && errorMessage !== 'nameTaken') {
                  this.error.set(errorMessage || 'Failed to create company');
               }
               this.isLoading.set(false);
            },
         });
   }

   createCompanyAdmin(): void {
      if (this.adminForm.invalid) {
         this.adminForm.markAllAsTouched();
         return;
      }

      const company = this.createdCompany();
      if (!company) {
         this.error.set(this.translateService.instant('errors.companyDataNotFound'));
         return;
      }

      // Clear any existing async validation errors
      const emailControl = this.adminForm.get('email');
      if (emailControl?.errors) {
         const { emailTaken, ...rest } = emailControl.errors;
         emailControl.setErrors(Object.keys(rest).length ? rest : null);
      }

      this.isLoading.set(true);
      this.error.set(null);

      const formData = this.adminForm.getRawValue() as CompanyAdminFormData;

      // Extract only uid and name for organization and company
      const orgData = {
         uid: company.organizationUID,
         name: company.organizationName,
      };

      const companyData = {
         uid: company.uid,
         name: company.name,
      };

      // Validate email availability before sending invite
      this.companyAdminService
         .isCompanyAdminEmailAvailable$(orgData.uid, companyData.uid, formData.email)
         .pipe(
            switchMap((isAvailable) => {
               if (!isAvailable) {
                  // If form is valid but this check fails (race condition or something), throw error
                  if (emailControl) {
                     emailControl.setErrors({ emailTaken: true });
                     emailControl.markAsTouched();
                  }
                  throw new Error('emailTaken');
               }

               // Email is available, proceed with sending invite
               return this.companyAdminService.sendCompanyAdminInvite$(formData, orgData, companyData, true);
            }),
            takeUntilDestroyed(this.destroyRef)
         )
         .subscribe({
            next: (message) => {
               this.isLoading.set(false);
               const successMessage = this.translateService.instant('snackBar.companyAndAdminCreatedSuccessfully', {
                  companyName: companyData.name,
                  email: formData.email
               });
               this.snackBarService.showSuccess(successMessage);
               this.dialogRef.close({
                  success: true,
                  message,
                  company: companyData,
                  admin: formData,
               });
            },
            error: (err) => {
               this.logger.error('Failed to send company admin invite', err);
               // Don't show error message for validation errors (they're shown on form controls)
               if (err?.message !== 'emailTaken') {
                  this.error.set(err?.message || this.translateService.instant('errors.failedToSendInvite'));
               }
               this.isLoading.set(false);
            },
         });
   }
}
