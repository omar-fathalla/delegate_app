import { inject, Injectable, Injector, runInInjectionContext } from "@angular/core";
import { CompanyType, CompanyTypes } from "@shared/types/company-types";
import { OrganizationType } from "@shared/types/organization-types";
import {
  Firestore,
  serverTimestamp,
  collection,
  query,
  where,
  doc,
  getDoc,
  increment,
  writeBatch,
  addDoc,
  getDocs,
  updateDoc,
} from "@angular/fire/firestore";
import { Storage, ref, deleteObject } from "@angular/fire/storage";
import { map } from "rxjs/operators";
import { Observable, from, firstValueFrom } from "rxjs";
import { runInContextHelper$ } from "@shared/utilities/runInInjection-factory";
import { normalizeName } from "@shared/utilities/name-normalizer";
import { CompanyRequestService } from "./company-request.service";
import { AuthService } from "../auth/auth.service";
import { CompanyDocumentKey } from "@shared/types/company-request-types";
import { LoggerService } from "@shared/services/logger/logger.service";
import { FirebaseFunctionsService } from "@core/service/firebase-functions/firebase-functions.service";

@Injectable({ providedIn: "root" })
export class CompanyService {
  private readonly collectionPath = "companies";
  private readonly firestore = inject(Firestore);
  private readonly storage = inject(Storage);
  private readonly injector = inject(Injector);
  private readonly runWithContext = runInContextHelper$();
  private readonly companyRequestService = inject(CompanyRequestService);
  private readonly authService = inject(AuthService);
  private readonly logger = inject(LoggerService);
  private readonly firebaseFunctionsService = inject(FirebaseFunctionsService);

  createCompany$(data: Pick<CompanyType, "name" | "type" | "organizationCode">): Observable<string> {
    return this.runWithContext(async () => {
      const companyData = {
        ...data,
        name: normalizeName(data.name),
        createdAt: this.withInjection(() => serverTimestamp()),
        updatedAt: this.withInjection(() => serverTimestamp()),
      };
      const collectionRef = this.withInjection(() => collection(this.firestore, this.collectionPath));
      const docRef = await this.runWithInjection(() => addDoc(collectionRef, companyData));
      return docRef.id;
    }, `Failed to create company`);
  }

  getCompanyById$(organizationUID: string, companyId: string): Observable<CompanyType | undefined> {
    return this.runWithContext(() => {
      const companyRef = this.withInjection(() =>
        doc(this.firestore, "organizations", organizationUID, "companies", companyId)
      );
      return from(this.runWithInjection(() => getDoc(companyRef)));
    }, `Failed to get company: ${companyId}`).pipe(
      map((snap) => {
        if (!snap.exists()) return undefined;
        return { uid: snap.id, ...snap.data() } as CompanyType;
      })
    );
  }

  getCompanies$(organizationUID: string): Observable<CompanyType[]> {
    return this.runWithContext(async () => {
      const companiesRef = this.withInjection(() =>
        collection(this.firestore, "organizations", organizationUID, "companies")
      );
      // Use getDocs for faster one-time fetch instead of collectionData real-time listener
      const snapshot = await this.runWithInjection(() => getDocs(companiesRef));
      return snapshot.docs.map((doc) => ({ ...doc.data(), uid: doc.id } as CompanyType));
    }, `Failed to get companies for organization: ${organizationUID}`);
  }

  getCompanyByCode$(organizationUID: string, code: string): Observable<CompanyType[]> {
    return this.runWithContext(() => {
      const companiesRef = this.withInjection(() =>
        collection(this.firestore, "organizations", organizationUID, "companies")
      );
      const q = this.withInjection(() => query(companiesRef, where("companyCodeInOrg", "==", code)));
      return from(this.runWithInjection(() => getDocs(q))).pipe(
        map((querySnapshot) =>
          querySnapshot.docs.map((doc) => ({ ...doc.data(), uid: doc.id } as CompanyType))
        )
      );
    }, `Failed to find company by code: ${code}`);
  }

  createCompanyWithOrganization$(
    organization: Pick<OrganizationType, "uid" | "code" | "name">,
    formData: { name: string; type: CompanyTypes; code: string }
  ): Observable<string> {
    return this.runWithContext(async () => {
      // Validate company code uniqueness within the organization
      const code = formData.code.trim();
      const isAvailable = await firstValueFrom(this.isCompanyCodeAvailable$(organization.uid, code));

      if (!isAvailable) {
        throw new Error(
          `A company with code "${code}" already exists in this organization. Please use a different code.`
        );
      }

      const batch = this.withInjection(() => writeBatch(this.firestore));

      // Create company document in hierarchical structure
      const companiesRef = this.withInjection(() =>
        collection(this.firestore, "organizations", organization.uid, "companies")
      );
      const companyRef = this.withInjection(() => doc(companiesRef));

      const companyData: Omit<CompanyType, "uid"> = {
        companyCodeInOrg: code, // Use normalized code
        name: normalizeName(formData.name),
        type: formData.type,
        commercialRegisterNumber: "",
        taxCardNumber: "",
        admins: 0,
        delegates: 0,
        deferredPayment: 0,
        hasDeferredPayment: false,
        organizationUID: organization.uid,
        organizationCode: organization.code,
        organizationName: normalizeName(organization.name),
        status: "Pending",
        documentUrls: {
          commercialRegister: "",
          taxCard: "",
        },
        createdAt: this.withInjection(() => serverTimestamp()),
        updatedAt: this.withInjection(() => serverTimestamp()),
      };

      batch.set(companyRef, companyData);

      // Increment companies count on organization document
      const orgRef = this.withInjection(() => doc(this.firestore, "organizations", organization.uid));
      batch.update(orgRef, {
        companies: this.withInjection(() => increment(1)),
        updatedAt: this.withInjection(() => serverTimestamp()),
      });

      // Commit batch
      await batch.commit();

      return companyRef.id;
    }, "Error creating company");
  }

  /**
   * Updates company documents (commercial register and tax card) with URLs and numbers.
   * @param changedDocumentKeys Optional: which document(s) were actually changed. If provided, only these documents will be included in the request.
   */
  updateCompanyDocuments$(
    organizationUID: string,
    companyUID: string,
    commercialRegisterUrl: string,
    commercialRegisterNumber: string,
    taxCardUrl: string,
    taxCardNumber: string,
    changedDocumentKeys?: CompanyDocumentKey | CompanyDocumentKey[]
  ): Observable<void> {
    return this.runWithContext(async () => {
      const companyRef = this.withInjection(() =>
        doc(this.firestore, "organizations", organizationUID, "companies", companyUID)
      );

      const companySnap = await this.runWithInjection(() => getDoc(companyRef));
      if (!companySnap.exists()) {
        throw new Error("Company not found.");
      }

      const company = { uid: companySnap.id, ...companySnap.data() } as CompanyType;
      const previousUrls = company.documentUrls || {};

      // Determine which keys to process
      let keysToProcess: CompanyDocumentKey[];
      if (changedDocumentKeys) {
        keysToProcess = Array.isArray(changedDocumentKeys)
          ? changedDocumentKeys
          : ([changedDocumentKeys] as CompanyDocumentKey[]);
      } else {
        keysToProcess = ["commercialRegister", "taxCard"];
      }

      const oldUrlsToDelete: string[] = [];
      for (const key of keysToProcess) {
        const prevUrl = previousUrls[key];
        const newUrl = key === "commercialRegister" ? commercialRegisterUrl : taxCardUrl;

        if (prevUrl && prevUrl !== newUrl) {
          oldUrlsToDelete.push(prevUrl);
        }
      }

      const batch = this.withInjection(() => writeBatch(this.firestore));
      batch.update(companyRef, {
        commercialRegisterNumber,
        taxCardNumber,
        documentUrls: {
          commercialRegister: commercialRegisterUrl,
          taxCard: taxCardUrl,
        },
        updatedAt: this.withInjection(() => serverTimestamp()),
      });

      await batch.commit();

      if (oldUrlsToDelete.length > 0) {
        await this.deleteCompanyDocumentFiles(oldUrlsToDelete);
      }

      // Create or update company request after documents are uploaded
      // This ensures documents are marked as "pending" for review
      const currentUser = this.authService.currentUser();
      if (currentUser) {
        // Build requestedData with only changed documents
        const requestedData: {
          commercialRegisterNumber?: string;
          taxCardNumber?: string;
          documentUrls: {
            commercialRegister?: string;
            taxCard?: string;
          };
        } = {
          documentUrls: {},
        };

        // Only include data for changed documents
        if (keysToProcess.includes("commercialRegister")) {
          requestedData.commercialRegisterNumber = commercialRegisterNumber;
          requestedData.documentUrls.commercialRegister = commercialRegisterUrl;
        }
        if (keysToProcess.includes("taxCard")) {
          requestedData.taxCardNumber = taxCardNumber;
          requestedData.documentUrls.taxCard = taxCardUrl;
        }

        const request$ = this.companyRequestService.createCompanyRequest$(
          organizationUID,
          companyUID,
          company,
          requestedData,
          {
            uid: currentUser.uid,
            displayName: currentUser.displayName || "",
          },
          changedDocumentKeys // Pass which document(s) were changed
        );
        await firstValueFrom(request$);
      }
    }, "Error updating company documents");
  }

  updateCompanyName$(organizationUID: string, companyUID: string, newName: string): Observable<void> {
    return this.runWithContext(async () => {
      const companyRef = this.withInjection(() =>
        doc(this.firestore, "organizations", organizationUID, "companies", companyUID)
      );
      const normalizedName = normalizeName(newName);
      await this.runWithInjection(() =>
        updateDoc(companyRef, {
          name: normalizedName,
          updatedAt: this.withInjection(() => serverTimestamp()),
        })
      );
    }, "Error updating company name");
  }

  /**
   * Checks whether a company code is unused within the given organization.
   */
  isCompanyCodeAvailable$(organizationUID: string, code: string): Observable<boolean> {
    return this.runWithContext(() => {
      const companiesRef = this.withInjection(() =>
        collection(this.firestore, "organizations", organizationUID, "companies")
      );
      const q = this.withInjection(() => query(companiesRef, where("companyCodeInOrg", "==", code)));
      return from(this.runWithInjection(() => getDocs(q))).pipe(
        map((querySnapshot) =>
          querySnapshot.docs.map((doc) => ({ ...doc.data(), uid: doc.id } as CompanyType))
        )
      );
    }, `Failed to check company code availability: ${code}`).pipe(map((results) => results.length === 0));
  }

  /**
   * Checks whether a company name is unused within the given organization.
   */
  isCompanyNameAvailable$(organizationUID: string, name: string): Observable<boolean> {
    return this.runWithContext(() => {
      const normalizedName = normalizeName(name);
      const companiesRef = this.withInjection(() =>
        collection(this.firestore, "organizations", organizationUID, "companies")
      );
      const q = this.withInjection(() => query(companiesRef, where("name", "==", normalizedName)));
      return from(this.runWithInjection(() => getDocs(q))).pipe(
        map((querySnapshot) =>
          querySnapshot.docs.map((doc) => ({ ...doc.data(), uid: doc.id } as CompanyType))
        )
      );
    }, `Failed to check company name availability: ${name}`).pipe(map((results) => results.length === 0));
  }

  /**
   * Increments the deferred payment amount for a company.
   * Called when a delegate is created with isDeductedFromCompany flag.
   */
  incrementDeferredPayment$(organizationUID: string, companyUID: string, amount: number): Observable<void> {
    return this.runWithContext(async () => {
      const companyRef = this.withInjection(() =>
        doc(this.firestore, "organizations", organizationUID, "companies", companyUID)
      );
      await this.runWithInjection(() =>
        updateDoc(companyRef, {
          deferredPayment: this.withInjection(() => increment(amount)),
          updatedAt: this.withInjection(() => serverTimestamp()),
        })
      );
    }, "Error incrementing deferred payment");
  }

  /**
   * Clears/resets the deferred payment amount for a company to 0.
   * Called when the organization confirms payment has been received.
   */
  clearDeferredPayment$(organizationUID: string, companyUID: string): Observable<void> {
    return this.runWithContext(async () => {
      const companyRef = this.withInjection(() =>
        doc(this.firestore, "organizations", organizationUID, "companies", companyUID)
      );
      await this.runWithInjection(() =>
        updateDoc(companyRef, {
          deferredPayment: 0,
          hasDeferredPayment: false,
          updatedAt: this.withInjection(() => serverTimestamp()),
        })
      );
    }, "Error clearing deferred payment");
  }

  private withInjection<T>(operation: () => T): T {
    return runInInjectionContext(this.injector, operation);
  }

  private runWithInjection<T>(operation: () => Promise<T> | T): Promise<T> {
    return Promise.resolve(runInInjectionContext(this.injector, operation));
  }

  private async deleteCompanyDocumentFiles(urls: string[]): Promise<void> {
    const uniqueUrls = Array.from(
      new Set(urls.map((url) => (typeof url === "string" ? url.trim() : "")).filter((url) => url.length > 0))
    );

    const deletions = uniqueUrls.map(async (url) => {
      try {
        await this.runWithInjection(() => deleteObject(ref(this.storage, url)));
      } catch (error: any) {
        this.logger.warn("Failed to delete old company document file", {
          url,
          code: error?.code,
          message: error?.message,
        });
      }
    });

    await Promise.all(deletions);
  }

  /**
   * Deletes a company and all its related data (delegates, admins, requests, storage files)
   */
  deleteCompany$(organizationUID: string, companyUID: string): Observable<void> {
    // Delegate deletion to Cloud Function to ensure Firestore, Storage, and Auth are cleaned up consistently
    return this.firebaseFunctionsService.deleteCompany$(organizationUID, companyUID);
  }
}
