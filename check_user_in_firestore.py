#!/usr/bin/env python3
"""
سكريبت للتحقق من دور المستخدم في Firestore
"""

import firebase_admin
from firebase_admin import credentials, firestore

# تهيئة Firebase
# ملاحظة: يجب أن يكون لديك ملف service account JSON
# يمكن تحميله من Firebase Console → Project Settings → Service Accounts

def check_user_role(phone_number):
    """
    التحقق من دور المستخدم في Firestore
    """
    try:
        # تهيئة Firebase (إذا لم يتم بالفعل)
        if not firebase_admin._apps:
            cred = credentials.Certificate('path/to/serviceAccountKey.json')
            firebase_admin.initialize_app(cred)
        
        db = firestore.client()
        
        # البحث عن المستخدم برقم الهاتف
        users_ref = db.collection('users')
        
        # جرب صيغ مختلفة لرقم الهاتف
        phone_formats = [
            phone_number,
            f'+2{phone_number}',
            f'+20{phone_number}',
            f'0{phone_number}',
        ]
        
        print(f"🔍 البحث عن المستخدم برقم: {phone_number}")
        print("=" * 50)
        
        user_found = False
        
        for phone_format in phone_formats:
            query = users_ref.where('phoneNumber', '==', phone_format).limit(1)
            docs = query.stream()
            
            for doc in docs:
                user_found = True
                user_data = doc.to_dict()
                
                print(f"\n✅ تم العثور على المستخدم!")
                print(f"📄 Document ID: {doc.id}")
                print(f"📞 Phone Number: {user_data.get('phoneNumber', 'N/A')}")
                print(f"👤 Name: {user_data.get('firstName', '')} {user_data.get('lastName', '')}")
                print(f"🎭 Role: {user_data.get('role', 'N/A')}")
                print(f"🏢 Organization UID: {user_data.get('organizationUID', 'N/A')}")
                print(f"🏭 Company UID: {user_data.get('companyUID', 'N/A')}")
                
                # التحقق من الدور
                role = user_data.get('role', '')
                if role == 'super-admin':
                    print("\n✅ الدور صحيح: super-admin")
                else:
                    print(f"\n❌ الدور خاطئ: '{role}'")
                    print("   يجب أن يكون: 'super-admin'")
                    print("\n🔧 لتعديل الدور:")
                    print(f"   1. افتح Firebase Console")
                    print(f"   2. اذهب إلى Firestore → users → {doc.id}")
                    print(f"   3. عدّل حقل 'role' إلى 'super-admin'")
                
                break
        
        if not user_found:
            print("\n❌ لم يتم العثور على المستخدم!")
            print(f"   رقم الهاتف: {phone_number}")
            print("\n🔍 تحقق من:")
            print("   1. رقم الهاتف صحيح")
            print("   2. المستخدم موجود في Firestore")
            print("   3. حقل 'phoneNumber' في الوثيقة")
        
        print("\n" + "=" * 50)
        
    except Exception as e:
        print(f"\n❌ خطأ: {e}")

if __name__ == '__main__':
    # رقم الهاتف المراد التحقق منه
    phone = '01508899965'
    check_user_role(phone)
